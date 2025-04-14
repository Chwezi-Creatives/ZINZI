import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For json.encode
import 'package:flutter_dotenv/flutter_dotenv.dart';
//import 'package:zinzi2/chefDashh.dartp';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io'; // For File
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:zinzi2/chef_dash8888.dart'; //Ensure this imports your Chef Dashboard

// --- Constants ---
final apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';
final imgurClientID = dotenv.env['IMGUR_CLIENT_ID'] ?? '';

// Predefined value lists
final List<String> responseTimes = [
  "Immediate",
  "1 Hour",
  "2 Hours",
  "4 Hours"
];
final List<String> teamSizes = ["1", "2", "3", "4", "5", "6+", "10+"];
final List<String> minNoticeOptions = [
  "1 hour notice",
  "1 day notice",
  "1 Week notice",
  "1 Month notice",
  "1 Quarter",
  "1 Year notice"
];
final List<String> allLanguages = [
  "English",
  "Runyankole",
  "Indian",
  "Rukiga",
  "Luganda",
  "Arabic",
  "Jewish",
  "Lusoga",
  "Lugbala",
  "Spanish",
  "French",
  "German",
  "Italian"
];
final List<String> allSpecialties = [
  "Barbeque",
  "Mixologists",
  "Baristers",
  "Pastry",
  "Ugandan",
  "Salads",
  "Juices",
  "Luwombo",
  "West African",
  "Ethiopian",
  "Eritrean",
  "Somali",
  "Congolese",
  "Thai",
  "Jewish",
  "Indian",
];
final List<String> allCertifications = [
  "None",
  "Food handling & Safety",
  "Culinary Arts",
  "Nutrition",
  "Pastry"
];
final List<String> allEquipment = [
  "None",
  "Plates",
  "Cups",
  "Grill",
  "Oven",
  "Measuring cups",
  "Tables",
  "Dishes",
  "Knife Set",
  "Cutting Board"
];
final List<String> allAvailability = [
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday"
];
final List<String> chefTypes = ["Individual", "Company"];

// Pricing constants
final List<String> perGigCategories = [
  '5 people',
  '10 people',
  '20+ people',
  '50+ people',
  '100+ people'
];
final Map<String, String> perGigCategoryKeys = {
  // Keys suitable for JSON
  '5 people': '5_people',
  '10 people': '10_people',
  '20+ people': '20_plus_people',
  '50+ people': '50_plus_people',
  '100+ people': '100_plus_people',
};

// --- Widget ---
class ChefDataFormNetwork extends StatefulWidget {
  @override
  _ChefDataFormNetworkState createState() => _ChefDataFormNetworkState();
}

class _ChefDataFormNetworkState extends State<ChefDataFormNetwork> {
  final _formKey = GlobalKey<FormState>();

  // --- Controllers ---
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  final TextEditingController phoneNumberController = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController imageUrlController =
      TextEditingController(); // Profile Image URL
  final TextEditingController startingPriceController = TextEditingController();
  final TextEditingController experienceController = TextEditingController();
  final TextEditingController bioController = TextEditingController();

  // Pricing Controllers
  late Map<String, TextEditingController> perGigPriceControllers;
  final TextEditingController monthlyPriceController = TextEditingController();

  // --- State Variables ---
  File? _profileImage;
  String locationDisplay = 'Tap icon to get location';

  // Sample Menu Image State
  List<File?> _sampleImages = List.filled(3, null);
  List<String?> _sampleImageUrls = List.filled(3, null);
  List<bool> _isUploadingSample = List.filled(3, false);

  // Multi-Select State
  List<String> equipment = [];
  List<String> languages = [];
  List<String> specialties = [];
  List<String> certifications = [];
  List<String> availability = [];

  // Loading and Visibility State
  bool _isLoading = false; // General loading (location fetch, final submit)
  bool _isUploadingProfileImage = false; // Specific for profile image upload
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;

  // Dropdown Selected Values
  String selectedResponseTime = responseTimes.first;
  String selectedTeamSize = teamSizes.first;
  String selectedMinNotice = minNoticeOptions.first;
  String selectedChefType = chefTypes.first; // Default to 'Individual'

  @override
  void initState() {
    super.initState();
    // Initialize Per Gig Price Controllers
    perGigPriceControllers = {
      for (var key in perGigCategoryKeys.values) key: TextEditingController()
    };
  }

  @override
  void dispose() {
    // Dispose all controllers
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    phoneNumberController.dispose();
    locationController.dispose();
    imageUrlController.dispose();
    startingPriceController.dispose();
    experienceController.dispose();
    bioController.dispose();
    monthlyPriceController.dispose();
    perGigPriceControllers.values.forEach((controller) => controller.dispose());
    super.dispose();
  }

  // --- Image Handling ---

  // Generic image picker and uploader
  Future<void> _pickAndUploadImage({
    required Function(File) onFilePicked,
    required Function(String) onUrlReceived,
    required Function(bool) setLoading,
    Function? onError,
  }) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final imageFile = File(pickedFile.path);
      onFilePicked(imageFile);
      setLoading(true);

      try {
        String imageUrl = await _uploadImageToImgur(imageFile);
        onUrlReceived(imageUrl);
        setLoading(false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Image uploaded successfully!'),
              backgroundColor: Colors.green),
        );
      } catch (e) {
        setLoading(false);
        if (onError != null) onError();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Image upload failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // Handler for Profile Image
  Future<void> pickProfileImage() async {
    await _pickAndUploadImage(
      onFilePicked: (file) => setState(() => _profileImage = file),
      onUrlReceived: (url) => imageUrlController.text = url,
      setLoading: (loading) =>
          setState(() => _isUploadingProfileImage = loading),
      onError: () => setState(() => _profileImage = null),
    );
  }

  // Handler for Sample Menu Images
  Future<void> pickSampleImage(int index) async {
    if (index < 0 || index >= 3) return;
    await _pickAndUploadImage(
      onFilePicked: (file) => setState(() => _sampleImages[index] = file),
      onUrlReceived: (url) => setState(() => _sampleImageUrls[index] = url),
      setLoading: (loading) =>
          setState(() => _isUploadingSample[index] = loading),
      onError: () => setState(() => _sampleImages[index] = null),
    );
  }

  // Upload to Imgur (Ensure IMGUR_CLIENT_ID is in .env)
  Future<String> _uploadImageToImgur(File image) async {
    if (imgurClientID.isEmpty) {
      throw Exception('Imgur Client ID is not configured.');
    }
    final String uploadUrl = 'https://api.imgur.com/3/image';
    final request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
    request.headers['Authorization'] = 'Client-ID $imgurClientID';
    request.files.add(await http.MultipartFile.fromPath('image', image.path));

    final response = await request.send();
    final responseData = await http.Response.fromStream(response);

    if (response.statusCode == 200) {
      final jsonResponse = json.decode(responseData.body);
      return jsonResponse['data']['link'];
    } else {
      print("Imgur Upload Error: ${responseData.body}");
      throw Exception(
          'Failed to upload image. Status Code: ${response.statusCode}');
    }
  }

  // --- Location Handling ---
  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoading = true;
    });
    try {
      // ... (Location permission checks and Geolocator.getCurrentPosition) ...
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services are disabled.');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied)
          throw Exception('Location permissions denied.');
      }
      if (permission == LocationPermission.deniedForever)
        throw Exception('Location permissions permanently denied.');

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      // Reverse Geocoding (Optional but nice for display)
      String displayAddress =
          "Lat: ${position.latitude.toStringAsFixed(4)}, Lon: ${position.longitude.toStringAsFixed(4)}";
      try {
        final String apiUrl =
            'https://geocode.maps.co/reverse?lat=${position.latitude}&lon=${position.longitude}';
        final response = await http.get(Uri.parse(apiUrl));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          displayAddress = data['display_name'] ?? displayAddress;
        }
      } catch (e) {
        print("Reverse geocoding failed: $e");
      }

      setState(() {
        locationController.text = displayAddress; // Store the address string
        locationDisplay = displayAddress;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Location Acquired: $displayAddress'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error getting location: $e'),
            backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // --- Form Submission ---
  Future<void> submitData() async {
    // --- Validation Checks ---
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Please fix the errors in the form.'),
            backgroundColor: Colors.orange),
      );
      return;
    }
    if (passwordController.text != confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Passwords do not match.'),
            backgroundColor: Colors.orange),
      );
      return;
    }
    if (imageUrlController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Please upload a profile image.'),
            backgroundColor: Colors.orange),
      );
      return;
    }
    if (locationController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Please acquire your location.'),
            backgroundColor: Colors.orange),
      );
      return;
    }
    // Optional: Validate at least one sample menu image
    if (_sampleImageUrls
        .where((url) => url != null && url.isNotEmpty)
        .isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Please upload at least one sample menu image.'),
            backgroundColor: Colors.orange),
      );
      return;
    }
    // Safeguard: Clear large group pricing if type is Individual
    if (selectedChefType == 'Individual') {
      final key50plus = perGigCategoryKeys['50+ people']!;
      final key100plus = perGigCategoryKeys['100+ people']!;
      if (perGigPriceControllers[key50plus]!.text.isNotEmpty ||
          perGigPriceControllers[key100plus]!.text.isNotEmpty) {
        print(
            "Warning: Individual chef type selected, but large group pricing fields have values. Clearing them before submission.");
        perGigPriceControllers[key50plus]?.clear();
        perGigPriceControllers[key100plus]?.clear();
      }
    }
    // --- End Validation ---

    setState(() {
      _isLoading = true;
    });

    // --- Prepare Pricing Data ---
    Map<String, dynamic> perGigPrices = {};
    perGigPriceControllers.forEach((key, controller) {
      double? price = double.tryParse(controller.text.trim());
      bool isLargeGroupKey = key == perGigCategoryKeys['50+ people']! ||
          key == perGigCategoryKeys['100+ people']!;
      // Include price only if valid AND allowed for the selected chef type
      if (price != null &&
          (selectedChefType == 'Company' || !isLargeGroupKey)) {
        perGigPrices[key] = price;
      }
    });
    double? monthlyPrice = double.tryParse(monthlyPriceController.text.trim());
    double? startingPrice =
        double.tryParse(startingPriceController.text.trim());

    Map<String, dynamic> pricingData = {
      // This map matches the expected JSONB structure
      'starting_price': startingPrice ?? 0.0,
      'per_gig': perGigPrices, // Map of per-gig prices
      'per_month': monthlyPrice // Can be null if not entered
    };

    // --- Prepare List Data for JSON Encoding ---
    List<String> finalSampleMenuUrls = _sampleImageUrls
        .where((url) => url != null && url.isNotEmpty)
        .cast<String>()
        .toList();

    // Encode lists to JSON strings
    String equipmentJson =
        json.encode(equipment.isEmpty ? ['None'] : equipment);
    String availabilityJson =
        json.encode(availability.isEmpty ? [] : availability);
    String languagesJson = json.encode(languages.isEmpty ? [] : languages);
    String specialtiesJson =
        json.encode(specialties.isEmpty ? [] : specialties);
    String certificationsJson =
        json.encode(certifications.isEmpty ? ['None'] : certifications);
    String sampleMenuJson =
        json.encode(finalSampleMenuUrls); // Encode the list of URLs

    // --- Prepare Full Payload ---
    final chefData = {
      // Personal & Account Info
      'name': nameController.text.trim(),
      'email': emailController.text.trim(),
      'password': passwordController.text.trim(), // Backend MUST hash this
      'image': imageUrlController.text.trim(),
      'phone_number': phoneNumberController.text.trim(),
      'location': locationController.text.trim(),

      // Chef Profile & Logistics
      'chef_type': selectedChefType, // 'Individual' or 'Company'
      'experience': int.tryParse(experienceController.text.trim()) ?? 0,
      'responsetime': selectedResponseTime,
      'minnotice': selectedMinNotice,
      'teamsize': selectedTeamSize,
      'bio': bioController.text.trim(),

      // System & Defaults
      'is_active': true,
      'rating': 0.0, // Ensure numeric if DB expects numeric
      'registration_date': DateTime.now().toIso8601String(),
      'last_login': DateTime.now().toIso8601String(),

      // Fields stored as JSON strings or JSONB
      'pricing': pricingData, // Send the map directly for JSONB
      'equipment': equipmentJson, // Send JSON string for TEXT column
      'availability': availabilityJson, // Send JSON string for TEXT column
      'languages': languagesJson, // Send JSON string for TEXT/VARCHAR column
      'specialties': specialtiesJson, // Send JSON string for TEXT column
      'certifications': certificationsJson, // Send JSON string for TEXT column
      'samplemenu': sampleMenuJson, // Send JSON string of URLs for TEXT column

      // Fields likely handled by backend:
      // 'chefid', 'is_email_verified', 'hashed_password', 'user_type',
      // 'serviceradius', 'punctuality', 'reviews', 'added_by', 'added_by_type'
    };

    // --- API Call ---
    final String apiUrl =
        '$apibaseurl/rr/signup_chef'; // Use your actual endpoint
    try {
      print(
          "Sending data to $apiUrl: ${json.encode(chefData)}"); // Log for debugging
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode(chefData), // Encode the whole map to JSON
      );

      print("API Response Status: ${response.statusCode}");
      print("API Response Body: ${response.body}");

      if (response.statusCode == 201) {
        // Check for successful creation status
        final responseData = json.decode(response.body);
        final int? chefID = responseData['ChefID'];
        final String? userType = responseData['UserType'];

        // Save essential session info if needed
        if (chefID != null && userType != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('ChefID', chefID);
          await prefs.setString('UserType', userType);
          print('Saved ChefID: $chefID, UserType: $userType');
        } else {
          print('ChefID or UserType is null in response, not saving.');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Chef registration successful!'),
              backgroundColor: Colors.green),
        );

        // Navigate to dashboard on success
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) =>
                  ChefDash88new()), // Ensure ChefDashboard exists
        );
      } else {
        // Handle API errors gracefully
        String errorMessage = 'Failed to submit data.';
        try {
          final errorData = json.decode(response.body);
          errorMessage +=
              ' Error: ${errorData['message'] ?? response.reasonPhrase}';
        } catch (_) {
          errorMessage +=
              ' Error: ${response.reasonPhrase} (Status code: ${response.statusCode})';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
        );
      }
    } catch (error) {
      // Handle network or other errors
      print("Submission Error: $error");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('An error occurred: $error'),
            backgroundColor: Colors.red),
      );
    } finally {
      // Ensure loading indicator stops
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // --- Build Method & UI Helpers ---

  // Consistent InputDecoration
  InputDecoration _buildInputDecoration(String label,
      {IconData? prefixIcon, Widget? suffixIcon, String? hintText}) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      labelStyle: TextStyle(color: Colors.teal[700]),
      hintStyle: TextStyle(color: Colors.grey[500]),
      prefixIcon:
          prefixIcon != null ? Icon(prefixIcon, color: Colors.teal) : null,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.teal[50]?.withOpacity(0.8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: Colors.teal.withOpacity(0.5), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: Colors.teal, width: 1.5),
      ),
      contentPadding: EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
    );
  }

  // MultiSelect Dialog Field Helper
  Widget _buildMultiSelectField({
    required String title,
    required List<String> allItems,
    required List<String> selectedItems,
    required Function(List<String>) onConfirm,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: MultiSelectDialogField(
        // Uses the custom MultiSelectDialogField below
        items: allItems.map((item) => MultiSelectItem(item, item)).toList(),
        title: title,
        decoration: _buildInputDecoration(title),
        buttonText: Text(
          selectedItems.isNotEmpty ? selectedItems.join(', ') : "Select $title",
          style: TextStyle(
              color: selectedItems.isNotEmpty
                  ? Colors.teal[900]
                  : Colors.grey[600],
              fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        onConfirm: onConfirm,
        buttonIcon: Icon(Icons.arrow_drop_down, color: Colors.teal),
        selectedColor: Colors.teal,
        dialogTextStyle: TextStyle(color: Colors.teal[900]),
        checkBoxCheckColor: Colors.white,
        checkBoxActiveColor: Colors.teal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chef Registration',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal[700],
        elevation: 4,
      ),
      body: Container(
        // Background Image with Overlay
        decoration: BoxDecoration(
          image: DecorationImage(
            image:
                AssetImage('assets/images/soft.jpg'), // Ensure path is correct
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.4), // Adjust darkness
              BlendMode.darken,
            ),
          ),
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: <Widget>[
              // --- Sections using Cards ---
              _buildProfileImagePickerSection(),
              SizedBox(height: 24),

              _buildSectionCard(
                title: 'Personal Information',
                icon: Icons.person_outline,
                children: [
                  _buildNameField(),
                  SizedBox(height: 16),
                  _buildEmailField(),
                  SizedBox(height: 16),
                  _buildPhoneField(),
                  SizedBox(height: 16),
                  _buildLocationSection(),
                ],
              ),
              SizedBox(height: 24),

              _buildSectionCard(
                title: 'Account Credentials',
                icon: Icons.lock_outline,
                children: [
                  _buildPasswordField(),
                  SizedBox(height: 16),
                  _buildConfirmPasswordField(),
                ],
              ),
              SizedBox(height: 24),

              _buildSectionCard(
                title: 'Chef Profile',
                icon: Icons.restaurant_menu,
                children: [
                  _buildChefTypeDropdown(),
                  SizedBox(
                      height: 16), // Contains Company/Individual logic trigger
                  _buildExperienceField(), SizedBox(height: 16),
                  _buildBioField(),
                ],
              ),
              SizedBox(height: 24),

              _buildSectionCard(
                title: 'Pricing Structure',
                icon: Icons.monetization_on_outlined,
                children: [
                  _buildStartingPriceField(), SizedBox(height: 20),
                  _buildPerGigPricingSection(),
                  SizedBox(height: 20), // Contains conditional fields
                  _buildMonthlyPriceField(),
                ],
              ),
              SizedBox(height: 24),

              _buildSectionCard(
                title: 'Logistics & Availability',
                icon: Icons.timer_outlined,
                children: [
                  _buildResponseTimeDropdown(), SizedBox(height: 16),
                  _buildMinNoticeDropdown(), SizedBox(height: 16),
                  _buildTeamSizeDropdown(), SizedBox(height: 16),
                  _buildAvailabilitySelector(), // Uses MultiSelect
                ],
              ),
              SizedBox(height: 24),

              _buildSectionCard(
                title: 'Skills & Equipment',
                icon: Icons.build_circle_outlined,
                children: [
                  _buildLanguagesSelector(),
                  SizedBox(height: 16), // Uses MultiSelect
                  _buildSpecialtiesSelector(),
                  SizedBox(height: 16), // Uses MultiSelect
                  _buildCertificationsSelector(),
                  SizedBox(height: 16), // Uses MultiSelect
                  _buildEquipmentSelector(), // Uses MultiSelect
                ],
              ),
              SizedBox(height: 24),

              _buildSectionCard(
                title: 'Samples',
                icon: Icons.photo_library_outlined,
                children: [
                  _buildSampleMenuImagesSection(), // Contains 3 image pickers
                ],
              ),
              SizedBox(height: 30),

              // Submit Button
              _buildSubmitButton(),
              SizedBox(height: 20), // Bottom padding
            ],
          ),
        ),
      ),
    );
  }

  // --- Reusable Section Card Widget ---
  Widget _buildSectionCard(
      {required String title,
      required IconData icon,
      required List<Widget> children}) {
    return Card(
      elevation: 3.0,
      margin: EdgeInsets.symmetric(vertical: 8.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
      color: Colors.white.withOpacity(0.95), // Slightly transparent card
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              // Title Row
              children: [
                Icon(icon, color: Colors.teal[600], size: 24.0),
                SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal[800]),
                ),
              ],
            ),
            Divider(height: 20, thickness: 1, color: Colors.teal[100]),
            ...children, // Add all the child widgets passed to the card
          ],
        ),
      ),
    );
  }

  // --- Individual Field/Section Builder Widgets ---

  Widget _buildProfileImagePickerSection() {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircleAvatar(
            radius: 60,
            backgroundColor: Colors.teal[100]?.withOpacity(0.8),
            backgroundImage:
                _profileImage != null ? FileImage(_profileImage!) : null,
            child: _profileImage == null && !_isUploadingProfileImage
                ? Icon(Icons.add_a_photo, size: 40, color: Colors.teal[700])
                : null,
          ),
          if (_isUploadingProfileImage)
            CircularProgressIndicator(color: Colors.teal),
          Positioned.fill(
            // Tappable overlay
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                  onTap: pickProfileImage,
                  borderRadius: BorderRadius.circular(60),
                  splashColor: Colors.teal.withOpacity(0.3)),
            ),
          ),
          if (!_isUploadingProfileImage &&
              imageUrlController.text.isNotEmpty) // Success checkmark
            Positioned(
              bottom: 0,
              right: 0,
              child: CircleAvatar(
                  radius: 15,
                  backgroundColor: Colors.green,
                  child: Icon(Icons.check, color: Colors.white, size: 20)),
            ),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: nameController,
      decoration: _buildInputDecoration('Full Name', prefixIcon: Icons.person),
      validator: (value) =>
          value == null || value.isEmpty ? 'Please enter your name' : null,
      style: TextStyle(color: Colors.teal[900]),
      textCapitalization: TextCapitalization.words,
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: emailController,
      decoration:
          _buildInputDecoration('Email Address', prefixIcon: Icons.email),
      keyboardType: TextInputType.emailAddress,
      validator: (value) {
        if (value == null || value.isEmpty) return 'Please enter an email';
        if (!RegExp(r'\S+@\S+\.\S+').hasMatch(value))
          return 'Please enter a valid email';
        return null;
      },
      style: TextStyle(color: Colors.teal[900]),
    );
  }

  Widget _buildPhoneField() {
    return TextFormField(
      controller: phoneNumberController,
      decoration:
          _buildInputDecoration('Phone Number', prefixIcon: Icons.phone),
      keyboardType: TextInputType.phone,
      // Add specific phone validation if needed (e.g., length, format)
      validator: (value) =>
          value == null || value.isEmpty ? 'Please enter a phone number' : null,
      style: TextStyle(color: Colors.teal[900]),
    );
  }

  Widget _buildLocationSection() {
    return Row(
      children: [
        Expanded(
          // Display field for location
          child: InputDecorator(
            decoration:
                _buildInputDecoration('Location', prefixIcon: Icons.location_on)
                    .copyWith(
              fillColor: Colors.grey[200]?.withOpacity(0.8),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                  borderSide: BorderSide(
                      color: Colors.grey.withOpacity(0.5), width: 1)),
            ),
            child: Text(locationDisplay,
                style: TextStyle(color: Colors.teal[900], fontSize: 16),
                overflow: TextOverflow.ellipsis),
          ),
        ),
        SizedBox(width: 8),
        IconButton(
          // Button to fetch location
          icon: Icon(Icons.my_location, color: Colors.teal[600]),
          onPressed: _isLoading
              ? null
              : _getCurrentLocation, // Disable while general loading
          tooltip: 'Get Current Location',
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: passwordController,
      decoration: _buildInputDecoration(
        'Password',
        prefixIcon: Icons.lock,
        suffixIcon: IconButton(
          icon: Icon(_passwordVisible ? Icons.visibility : Icons.visibility_off,
              color: Colors.teal[700]),
          onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
        ),
      ),
      obscureText: !_passwordVisible,
      validator: (value) => value == null || value.length < 6
          ? 'Password must be at least 6 characters'
          : null,
      style: TextStyle(color: Colors.teal[900]),
    );
  }

  Widget _buildConfirmPasswordField() {
    return TextFormField(
      controller: confirmPasswordController,
      decoration: _buildInputDecoration(
        'Confirm Password',
        prefixIcon: Icons.lock_outline,
        suffixIcon: IconButton(
          icon: Icon(
              _confirmPasswordVisible ? Icons.visibility : Icons.visibility_off,
              color: Colors.teal[700]),
          onPressed: () => setState(
              () => _confirmPasswordVisible = !_confirmPasswordVisible),
        ),
      ),
      obscureText: !_confirmPasswordVisible,
      validator: (value) {
        if (value == null || value.isEmpty)
          return 'Please confirm your password';
        if (value != passwordController.text) return 'Passwords do not match';
        return null;
      },
      style: TextStyle(color: Colors.teal[900]),
    );
  }

  Widget _buildChefTypeDropdown() {
    // This dropdown now triggers the logic to clear/enable pricing fields
    return DropdownButtonFormField<String>(
      value: selectedChefType,
      decoration: _buildInputDecoration('I am registering as a/an:',
          prefixIcon: Icons.business_center_outlined),
      onChanged: (newValue) {
        if (newValue != null && newValue != selectedChefType) {
          setState(() {
            selectedChefType = newValue;
            // Clear large group prices if switching back to Individual
            if (newValue == 'Individual') {
              final key50plus = perGigCategoryKeys['50+ people']!;
              final key100plus = perGigCategoryKeys['100+ people']!;
              perGigPriceControllers[key50plus]?.clear();
              perGigPriceControllers[key100plus]?.clear();
              print(
                  "Switched to Individual, cleared large group pricing fields.");
            }
          });
        }
      },
      items: chefTypes.map((String type) {
        return DropdownMenuItem<String>(
            value: type,
            child: Text(type, style: TextStyle(color: Colors.teal[900])));
      }).toList(),
      style: TextStyle(color: Colors.teal[900], fontSize: 16),
      iconEnabledColor: Colors.teal[700],
      validator: (value) =>
          value == null ? 'Please select your registration type' : null,
    );
  }

  Widget _buildExperienceField() {
    return TextFormField(
      controller: experienceController,
      decoration: _buildInputDecoration('Experience (Years)',
          prefixIcon: Icons.star_border),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: (value) {
        if (value == null || value.isEmpty) return 'Enter years of experience';
        if (int.tryParse(value) == null)
          return 'Please enter a valid whole number';
        return null;
      },
      style: TextStyle(color: Colors.teal[900]),
    );
  }

  Widget _buildBioField() {
    return TextFormField(
      controller: bioController,
      decoration:
          _buildInputDecoration('Short Bio', prefixIcon: Icons.info_outline)
              .copyWith(
                  hintText:
                      'Tell clients about yourself and your cooking style...'),
      maxLines: 4,
      validator: (value) =>
          value == null || value.isEmpty ? 'Please enter a short bio' : null,
      style: TextStyle(color: Colors.teal[900]),
      textCapitalization: TextCapitalization.sentences,
    );
  }

  Widget _buildStartingPriceField() {
    return TextFormField(
      controller: startingPriceController,
      decoration: _buildInputDecoration('Starting Price (Optional)',
          prefixIcon: Icons.price_check,
          hintText: "e.g., Base price for a small event"),
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
      ],
      validator: (value) {
        // Optional validation
        if (value != null &&
            value.isNotEmpty &&
            double.tryParse(value) == null) {
          return 'Please enter a valid number';
        }
        return null;
      },
      style: TextStyle(color: Colors.teal[900]),
    );
  }

  Widget _buildPerGigPricingSection() {
    // This section now conditionally enables/disables fields
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("Per Gig Pricing (Optional)",
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.teal[800])),
      SizedBox(height: 4),
      Text("Enter price based on the number of guests:",
          style: TextStyle(fontSize: 14, color: Colors.grey[600])),
      SizedBox(height: 12),
      Column(
          children: perGigCategories.map((category) {
        final controllerKey = perGigCategoryKeys[category]!;
        final bool isLargeGroupCategory =
            category == '50+ people' || category == '100+ people';
        final bool isEnabled = !isLargeGroupCategory ||
            selectedChefType == 'Company'; // THE CORE LOGIC

        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              flex: 2,
              child: Text(category,
                  style: TextStyle(
                      color: isEnabled ? Colors.teal[900] : Colors.grey[500],
                      fontSize: 15)),
            ),
            SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: perGigPriceControllers[controllerKey],
                enabled: isEnabled, // Apply enabled state
                decoration: _buildInputDecoration("Price",
                        prefixIcon: Icons.attach_money)
                    .copyWith(
                  contentPadding:
                      EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
                  labelText: null,
                  fillColor: isEnabled
                      ? Colors.teal[50]?.withOpacity(0.8)
                      : Colors.grey[300]?.withOpacity(0.7),
                  hintText: !isEnabled ? 'Company only' : null,
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
                ],
                validator: (value) {
                  // Only validate if enabled and not empty
                  if (isEnabled &&
                      value != null &&
                      value.isNotEmpty &&
                      double.tryParse(value) == null) {
                    return 'Invalid number';
                  }
                  return null;
                },
                style: TextStyle(
                    color: isEnabled ? Colors.teal[900] : Colors.grey[700]),
              ),
            ),
          ]),
        );
      }).toList()),
    ]);
  }

  Widget _buildMonthlyPriceField() {
    return TextFormField(
      controller: monthlyPriceController,
      decoration: _buildInputDecoration('Fixed Monthly Price (Optional)',
          prefixIcon: Icons.calendar_today_outlined,
          hintText: "e.g., For retainer services"),
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))
      ],
      validator: (value) {
        // Optional validation
        if (value != null &&
            value.isNotEmpty &&
            double.tryParse(value) == null) {
          return 'Please enter a valid number';
        }
        return null;
      },
      style: TextStyle(color: Colors.teal[900]),
    );
  }

  Widget _buildResponseTimeDropdown() {
    return DropdownButtonFormField<String>(
      value: selectedResponseTime,
      decoration: _buildInputDecoration('Typical Response Time',
          prefixIcon: Icons.reply),
      onChanged: (newValue) {
        if (newValue != null) setState(() => selectedResponseTime = newValue);
      },
      items: responseTimes
          .map((time) => DropdownMenuItem(
              value: time,
              child: Text(time, style: TextStyle(color: Colors.teal[900]))))
          .toList(),
      style: TextStyle(color: Colors.teal[900], fontSize: 16),
      iconEnabledColor: Colors.teal[700],
      validator: (value) =>
          value == null ? 'Please select response time' : null,
    );
  }

  Widget _buildMinNoticeDropdown() {
    return DropdownButtonFormField<String>(
      value: selectedMinNotice,
      decoration: _buildInputDecoration('Minimum Booking Notice',
          prefixIcon: Icons.event_available),
      onChanged: (newValue) {
        if (newValue != null) setState(() => selectedMinNotice = newValue);
      },
      items: minNoticeOptions
          .map((notice) => DropdownMenuItem(
              value: notice,
              child: Text(notice, style: TextStyle(color: Colors.teal[900]))))
          .toList(),
      style: TextStyle(color: Colors.teal[900], fontSize: 16),
      iconEnabledColor: Colors.teal[700],
      validator: (value) =>
          value == null ? 'Please select minimum notice' : null,
    );
  }

  Widget _buildTeamSizeDropdown() {
    return DropdownButtonFormField<String>(
      value: selectedTeamSize,
      decoration:
          _buildInputDecoration('Team Size', prefixIcon: Icons.people_outline),
      onChanged: (newValue) {
        if (newValue != null) setState(() => selectedTeamSize = newValue);
      },
      items: teamSizes
          .map((size) => DropdownMenuItem(
              value: size,
              child: Text(size, style: TextStyle(color: Colors.teal[900]))))
          .toList(),
      style: TextStyle(color: Colors.teal[900], fontSize: 16),
      iconEnabledColor: Colors.teal[700],
      validator: (value) => value == null ? 'Please select team size' : null,
    );
  }

  Widget _buildAvailabilitySelector() {
    return _buildMultiSelectField(
      title: 'Availability',
      allItems: allAvailability,
      selectedItems: availability,
      onConfirm: (values) => setState(() => availability = values),
    );
  }

  Widget _buildLanguagesSelector() {
    return _buildMultiSelectField(
      title: 'Languages Spoken',
      allItems: allLanguages,
      selectedItems: languages,
      onConfirm: (values) => setState(() => languages = values),
    );
  }

  Widget _buildSpecialtiesSelector() {
    return _buildMultiSelectField(
      title: 'Cuisine Specialties',
      allItems: allSpecialties,
      selectedItems: specialties,
      onConfirm: (values) => setState(() => specialties = values),
    );
  }

  Widget _buildCertificationsSelector() {
    return _buildMultiSelectField(
      title: 'Certifications',
      allItems: allCertifications,
      selectedItems: certifications,
      onConfirm: (values) => setState(() => certifications = values),
    );
  }

  Widget _buildEquipmentSelector() {
    return _buildMultiSelectField(
      title: 'Equipment Provided',
      allItems: allEquipment,
      selectedItems: equipment,
      onConfirm: (values) => setState(() => equipment = values),
    );
  }

  Widget _buildSampleMenuImagesSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("Upload up to 3 images of your best dishes:",
          style: TextStyle(color: Colors.teal[800], fontSize: 15)),
      SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(3, (index) {
          return _buildImagePickerSlot(
            index: index,
            imageFile: _sampleImages[index],
            imageUrl: _sampleImageUrls[index],
            isLoading: _isUploadingSample[index],
            onTap: () => pickSampleImage(index),
          );
        }),
      ),
    ]);
  }

  // Helper widget for a single image picker slot
  Widget _buildImagePickerSlot(
      {required int index,
      required File? imageFile,
      required String? imageUrl,
      required bool isLoading,
      required VoidCallback onTap}) {
    return Column(children: [
      GestureDetector(
        onTap: isLoading ? null : onTap,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.grey[200]?.withOpacity(0.8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.teal.withOpacity(0.5)),
            image: imageFile != null
                ? DecorationImage(
                    image: FileImage(imageFile), fit: BoxFit.cover)
                : null,
          ),
          child: Stack(alignment: Alignment.center, children: [
            if (imageFile == null && !isLoading)
              Icon(Icons.add_photo_alternate_outlined,
                  color: Colors.teal[600], size: 30),
            if (isLoading)
              CircularProgressIndicator(strokeWidth: 2, color: Colors.teal),
            if (!isLoading && imageUrl != null)
              Positioned(
                  top: 4,
                  right: 4,
                  child: CircleAvatar(
                      radius: 10,
                      backgroundColor: Colors.green,
                      child: Icon(Icons.check, size: 14, color: Colors.white))),
          ]),
        ),
      ),
      SizedBox(height: 4),
      Text("Image ${index + 1}",
          style: TextStyle(fontSize: 12, color: Colors.grey[700]))
    ]);
  }

  Widget _buildSubmitButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : submitData, // Disable button when loading
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.teal[700],
        padding: EdgeInsets.symmetric(vertical: 16.0),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        textStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ).copyWith(
          // Handle disabled state appearance
          foregroundColor: MaterialStateProperty.resolveWith<Color>((states) =>
              states.contains(MaterialState.disabled)
                  ? Colors.grey[400]!
                  : Colors.white),
          backgroundColor: MaterialStateProperty.resolveWith<Color>((states) =>
              states.contains(MaterialState.disabled)
                  ? Colors.teal[700]!.withOpacity(0.5)
                  : Colors.teal[700]!)),
      child: _isLoading
          ? SizedBox(
              height: 24.0,
              width: 24.0,
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 3.0))
          : Text('Register as Chef', style: TextStyle(color: Colors.white)),
    );
  }
} // End of _ChefDataFormNetworkState

// --- MultiSelect Dialog Widgets ---
// (These remain unchanged from previous versions, ensure they are included)

class MultiSelectDialogField extends StatelessWidget {
  final List<MultiSelectItem> items;
  final String title;
  final Widget buttonText;
  final Function(List<String>) onConfirm;
  final InputDecoration decoration;
  final Icon buttonIcon;
  final Color selectedColor;
  final TextStyle dialogTextStyle;
  final Color? checkBoxCheckColor;
  final Color? checkBoxActiveColor;

  MultiSelectDialogField({
    required this.items,
    required this.title,
    required this.buttonText,
    required this.onConfirm,
    required this.decoration,
    required this.buttonIcon,
    required this.selectedColor,
    required this.dialogTextStyle,
    this.checkBoxCheckColor,
    this.checkBoxActiveColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        // Determine current selection from button text to pre-fill dialog
        List<String> currentSelection = [];
        if (buttonText is Text) {
          final text = (buttonText as Text).data ?? "";
          if (!text.startsWith("Select")) {
            // Basic check if something is selected
            currentSelection = text
                .split(', ')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
          }
        }
        final selectedValues = await showDialog<List<String>>(
          context: context,
          builder: (BuildContext context) {
            return MultiSelectDialog(
              items: items,
              title: title,
              initialSelectedValues: currentSelection,
              selectedColor: selectedColor,
              dialogTextStyle: dialogTextStyle,
              checkBoxCheckColor: checkBoxCheckColor,
              checkBoxActiveColor: checkBoxActiveColor,
            );
          },
        );
        if (selectedValues != null) {
          onConfirm(selectedValues);
        }
      },
      child: InputDecorator(
        decoration:
            decoration.copyWith(labelText: title), // Ensure label stays above
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[Expanded(child: buttonText), buttonIcon],
        ),
      ),
    );
  }
}

class MultiSelectDialog extends StatefulWidget {
  final String title;
  final List<MultiSelectItem> items;
  final List<String>? initialSelectedValues;
  final Color selectedColor;
  final TextStyle dialogTextStyle;
  final Color? checkBoxCheckColor;
  final Color? checkBoxActiveColor;

  MultiSelectDialog({
    required this.title,
    required this.items,
    this.initialSelectedValues,
    required this.selectedColor,
    required this.dialogTextStyle,
    this.checkBoxCheckColor,
    this.checkBoxActiveColor,
  });

  @override
  State<MultiSelectDialog> createState() => _MultiSelectDialogState();
}

class _MultiSelectDialogState extends State<MultiSelectDialog> {
  late List<String> selectedItems;

  @override
  void initState() {
    super.initState();
    // Create a mutable copy of initial values
    selectedItems = List<String>.from(widget.initialSelectedValues ?? []);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
      title: Text(widget.title,
          style:
              TextStyle(color: Colors.teal[800], fontWeight: FontWeight.bold)),
      content: Container(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true, // Important for AlertDialog content
          itemCount: widget.items.length,
          itemBuilder: (context, index) {
            final item = widget.items[index];
            final bool isSelected = selectedItems.contains(item.value);
            return CheckboxListTile(
              title: Text(item.label, style: widget.dialogTextStyle),
              value: isSelected,
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    selectedItems.add(item.value);
                  } else {
                    selectedItems.remove(item.value);
                  }
                });
              },
              activeColor: widget.checkBoxActiveColor ?? widget.selectedColor,
              checkColor: widget.checkBoxCheckColor ?? Colors.white,
              controlAffinity:
                  ListTileControlAffinity.leading, // Checkbox on left
            );
          },
        ),
      ),
      actions: [
        TextButton(
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
            onPressed: () => Navigator.pop(context)),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: widget.selectedColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0))),
          child: Text('Ok', style: TextStyle(color: Colors.white)),
          onPressed: () =>
              Navigator.pop(context, selectedItems), // Return selected items
        ),
      ],
    );
  }
}

// Data class for MultiSelect items
class MultiSelectItem {
  final String label;
  final String value;
  MultiSelectItem(this.label, this.value);
}
