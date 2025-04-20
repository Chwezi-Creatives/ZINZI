import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // For json.encode
import 'dart:async'; // For Timer and TimeoutException
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io'; // For File
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:zinzi2/chef_dash8888.dart'; //Ensure this imports your Chef Dashboard

// --- Consistent Color Palette ---
const Color primaryTeal = Color(0xFF00796B); // Teal 700
const Color lightTeal = Color(0xFFB2DFDB); // Teal 100
const Color lighterTeal = Color(0xFFE0F2F1); // Teal 50
const Color darkTeal = Color(0xFF004D40); // Teal 900
const Color accentTeal = Color(0xFF009688); // Teal 500
const Color whiteColor = Colors.white; // Main background color
const Color textFieldFillColor = Color(0xFFF5F5F5); // Light grey fill for inputs on white BG
const Color subtleTextColor = Color(0xFF757575); // Grey 600
const Color errorColor = Color(0xFFD32F2F); // Red 700 for errors
const Color disabledColor = Colors.grey;

// --- API Base URL & Config ---
final apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';
final imgurClientID = dotenv.env['IMGUR_CLIENT_ID'] ?? '';

// --- Predefined value lists (Keep as is) ---
final List<String> responseTimes = ["Immediate", "1 Hour", "2 Hours", "4 Hours"];
final List<String> teamSizes = ["1", "2", "3", "4", "5", "6+", "10+"];
final List<String> minNoticeOptions = ["1 hour notice", "1 day notice", "1 Week notice", "1 Month notice", "1 Quarter", "1 Year notice"];
final List<String> allLanguages = ["English", "Runyankole", "Indian", "Rukiga", "Luganda", "Arabic", "Jewish", "Lusoga", "Lugbala", "Spanish", "French", "German", "Italian"];
final List<String> allSpecialties = ["Barbeque", "Mixologists", "Baristers", "Pastry", "Ugandan", "Salads", "Juices", "Luwombo", "West African", "Ethiopian", "Eritrean", "Somali", "Congolese", "Thai", "Jewish", "Indian"];
final List<String> allCertifications = ["None", "Food handling & Safety", "Culinary Arts", "Nutrition", "Pastry"];
final List<String> allEquipment = ["None", "Plates", "Cups", "Grill", "Oven", "Measuring cups", "Tables", "Dishes", "Knife Set", "Cutting Board"];
final List<String> allAvailability = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
final List<String> chefTypes = ["Individual", "Company"];
final List<String> perGigCategories = ['5 people', '10 people', '20+ people', '50+ people', '100+ people'];
final Map<String, String> perGigCategoryKeys = {'5 people': '5_people', '10 people': '10_people', '20+ people': '20_plus_people', '50+ people': '50_plus_people', '100+ people': '100_plus_people'};


// --- Widget ---
class ChefSignUpPageBetterNew extends StatefulWidget {
  const ChefSignUpPageBetterNew({super.key}); // Add key

  @override
  _ChefSignUpPageBetterNewState createState() => _ChefSignUpPageBetterNewState();
}

class _ChefSignUpPageBetterNewState extends State<ChefSignUpPageBetterNew> {
  final _formKey = GlobalKey<FormState>();

  // --- Controllers (Keep all original controllers) ---
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  final TextEditingController phoneNumberController = TextEditingController();
  final TextEditingController locationController = TextEditingController(); // Stores final location string
  final TextEditingController imageUrlController = TextEditingController(); // Profile Image URL
  final TextEditingController startingPriceController = TextEditingController();
  final TextEditingController experienceController = TextEditingController();
  final TextEditingController bioController = TextEditingController();
  final TextEditingController monthlyPriceController = TextEditingController();
  late Map<String, TextEditingController> perGigPriceControllers;

  // --- State Variables (Keep original + Add new ones for UI/Location) ---
  File? _profileImage;

  List<File?> _sampleImages = List.filled(3, null);
  List<String?> _sampleImageUrls = List.filled(3, null);
  List<bool> _isUploadingSample = List.filled(3, false);

  List<String> equipment = [];
  List<String> languages = [];
  List<String> specialties = [];
  List<String> certifications = [];
  List<String> availability = [];

  // --- NEW/MODIFIED State Variables ---
  bool _isLoading = false; // General loading for FINAL submit
  bool _isFetchingLocation = false; // Specific state for location fetching
  bool _isUploadingProfileImage = false; // Specific for profile image upload
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;
  Timer? _locationHintTimer; // For location fetch animation
  int _locationHintDots = 0; // For location fetch animation


  String selectedResponseTime = responseTimes.first;
  String selectedTeamSize = teamSizes.first;
  String selectedMinNotice = minNoticeOptions.first;
  String selectedChefType = chefTypes.first;

  @override
  void initState() {
    super.initState();
    perGigPriceControllers = { for (var key in perGigCategoryKeys.values) key: TextEditingController() };
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
    _locationHintTimer?.cancel(); // Dispose animation timer
    super.dispose();
  }

  // --- Image Handling ---
   Future<void> _pickAndUploadImage({
    required Function(File) onFilePicked,
    required Function(String) onUrlReceived,
    required Function(bool) setLoading,
    Function? onError,
  }) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 800);

    if (pickedFile != null) {
      final imageFile = File(pickedFile.path);
      onFilePicked(imageFile);
      setLoading(true);

      try {
        String imageUrl = await _uploadImageToImgur(imageFile);
        onUrlReceived(imageUrl);
        _showSnackBar('Image uploaded successfully!', isError: false);
      } catch (e) {
        if (onError != null) onError();
         _showSnackBar('Image upload failed: $e', isError: true);
      } finally {
         setLoading(false);
      }
    }
  }

  Future<void> pickProfileImage() async {
    await _pickAndUploadImage(
      onFilePicked: (file) => setState(() => _profileImage = file),
      onUrlReceived: (url) => imageUrlController.text = url,
      setLoading: (loading) => setState(() => _isUploadingProfileImage = loading),
      onError: () => setState(() => _profileImage = null),
    );
  }

  Future<void> pickSampleImage(int index) async {
    if (index < 0 || index >= 3) return;
    await _pickAndUploadImage(
      onFilePicked: (file) => setState(() => _sampleImages[index] = file),
      onUrlReceived: (url) => setState(() => _sampleImageUrls[index] = url),
      setLoading: (loading) => setState(() => _isUploadingSample[index] = loading),
      onError: () => setState(() => _sampleImages[index] = null),
    );
  }

  Future<String> _uploadImageToImgur(File image) async {
    if (imgurClientID.isEmpty) throw Exception('Imgur Client ID is not configured.');

    var request = http.MultipartRequest('POST', Uri.parse('https://api.imgur.com/3/image'));
    request.headers['Authorization'] = 'Client-ID $imgurClientID';
    request.files.add(await http.MultipartFile.fromPath('image', image.path));

    final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final jsonResponse = json.decode(response.body);
      if (jsonResponse['success'] == true && jsonResponse['data']?['link'] != null) {
          return jsonResponse['data']['link'];
      } else {
         throw Exception('Imgur upload failed: Invalid response structure.');
      }
    } else {
      print("Imgur Upload Error: ${response.body}");
      throw Exception('Failed to upload image. Status Code: ${response.statusCode}');
    }
  }

  // --- Location Handling (Adapted from ChefSignUpPage) ---

  void _startLocationHintAnimation() {
    _locationHintTimer?.cancel();
    _locationHintDots = 0;
    _locationHintTimer = Timer.periodic(const Duration(milliseconds: 400), (timer) {
      if (!mounted || !_isFetchingLocation) {
        timer.cancel();
        if (mounted && !_isFetchingLocation) setState(() => _locationHintDots = 0);
        return;
      }
      setState(() => _locationHintDots = (_locationHintDots + 1) % 4);
    });
  }

  void _stopLocationHintAnimation() {
    _locationHintTimer?.cancel();
    if (mounted) setState(() => _locationHintDots = 0);
  }

  // --- CORRECTED _getCurrentLocation ---
  Future<void> _getCurrentLocation() async {
    if (_isFetchingLocation) return;

    setState(() {
      _isFetchingLocation = true; // Use specific flag
      locationController.clear(); // Clear the data controller
    });
    _startLocationHintAnimation();

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('Location services are disabled.');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) throw Exception('Location permissions denied.');
      }
      if (permission == LocationPermission.deniedForever) throw Exception('Location permissions permanently denied.');

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15));

      // Reverse Geocoding
      String displayAddress = "Lat: ${position.latitude.toStringAsFixed(4)}, Lon: ${position.longitude.toStringAsFixed(4)}";
      String coords = "${position.latitude}, ${position.longitude}"; // Store coordinates separately

      try {
        final String apiUrl = 'https://geocode.maps.co/reverse?lat=${position.latitude}&lon=${position.longitude}';
        final response = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          // Use the fetched address if available and valid
          displayAddress = data['display_name'] ?? displayAddress;
        } else {
           print("Reverse geocode error: ${response.statusCode}");
           // Keep displayAddress as coordinates, show snackbar
           _showSnackBar('Could not fetch readable address.', isError: true);
        }
      } catch (e) {
         // Keep displayAddress as coordinates, show snackbar
         print("Reverse geocode exception: $e");
         // ERROR LINE REMOVED FROM HERE
         _showSnackBar('Could not fetch readable address.', isError: true);
      }

       _stopLocationHintAnimation();
       setState(() {
         // Update the text controller with the best available address string
         // Add coordinates in parentheses for clarity/storage if needed
         locationController.text = (displayAddress.isNotEmpty && !displayAddress.startsWith("Lat:"))
            ? "$displayAddress ($coords)"
            : "Location Acquired ($coords)"; // Fallback if address failed or wasn't found
         _isFetchingLocation = false;
      });
      _showSnackBar('Location acquired successfully!', isError: false);

    } on TimeoutException catch (_) {
       _stopLocationHintAnimation();
       setState(() {
          _isFetchingLocation = false;
          locationController.text = 'Failed to get location (Timeout)'; // Indicate failure in field
       });
       _showSnackBar('Getting location timed out.', isError: true);
    } catch (e) {
       _stopLocationHintAnimation();
       setState(() {
          _isFetchingLocation = false;
          locationController.text = 'Failed to get location'; // Indicate failure in field
       });
      _showSnackBar('Error getting location: $e', isError: true);
    }
  }
  // --- End CORRECTED _getCurrentLocation ---


  // --- Form Submission (Keep existing logic) ---
  Future<void> submitData() async {
    // --- Validation Checks ---
    if (!_formKey.currentState!.validate()) {
      _showSnackBar('Please fix the errors in the form.', isError: true, isWarning: true);
      return;
    }
    if (passwordController.text != confirmPasswordController.text) {
      _showSnackBar('Passwords do not match.', isError: true, isWarning: true);
      return;
    }
    if (imageUrlController.text.isEmpty) {
      _showSnackBar('Please upload a profile image.', isError: true, isWarning: true);
      return;
    }
    if (locationController.text.isEmpty || locationController.text.startsWith('Failed to get location')) {
      _showSnackBar('Please acquire your location.', isError: true, isWarning: true);
       _formKey.currentState!.validate();
      return;
    }
    if (_sampleImageUrls.where((url) => url != null && url.isNotEmpty).isEmpty) {
      _showSnackBar('Please upload at least one sample menu image.', isError: true, isWarning: true);
      return;
    }
    if (selectedChefType == 'Individual') {
      final key50plus = perGigCategoryKeys['50+ people']!;
      final key100plus = perGigCategoryKeys['100+ people']!;
      if (perGigPriceControllers[key50plus]!.text.isNotEmpty || perGigPriceControllers[key100plus]!.text.isNotEmpty) {
        print("Clearing large group pricing for Individual chef.");
        perGigPriceControllers[key50plus]?.clear();
        perGigPriceControllers[key100plus]?.clear();
      }
    }
    // --- End Validation ---

    setState(() => _isLoading = true); // General submit loading

    // --- Prepare Pricing Data ---
    Map<String, dynamic> perGigPrices = {};
    perGigPriceControllers.forEach((key, controller) {
      double? price = double.tryParse(controller.text.trim());
      bool isLargeGroupKey = key == perGigCategoryKeys['50+ people']! || key == perGigCategoryKeys['100+ people']!;
      if (price != null && (selectedChefType == 'Company' || !isLargeGroupKey)) {
        perGigPrices[key] = price;
      }
    });
    double? monthlyPrice = double.tryParse(monthlyPriceController.text.trim());
    double? startingPrice = double.tryParse(startingPriceController.text.trim());
    Map<String, dynamic> pricingData = {'starting_price': startingPrice ?? 0.0, 'per_gig': perGigPrices, 'per_month': monthlyPrice};

    // --- Prepare List Data ---
    List<String> finalSampleMenuUrls = _sampleImageUrls.where((url) => url != null && url.isNotEmpty).cast<String>().toList();
    String equipmentJson = json.encode(equipment.isEmpty ? ['None'] : equipment);
    String availabilityJson = json.encode(availability.isEmpty ? [] : availability);
    String languagesJson = json.encode(languages.isEmpty ? [] : languages);
    String specialtiesJson = json.encode(specialties.isEmpty ? [] : specialties);
    String certificationsJson = json.encode(certifications.isEmpty ? ['None'] : certifications);
    String sampleMenuJson = json.encode(finalSampleMenuUrls);

    // --- Prepare Full Payload ---
    final chefData = {
      'name': nameController.text.trim(), 'email': emailController.text.trim(),
      'password': passwordController.text.trim(), 'image': imageUrlController.text.trim(),
      'phone_number': phoneNumberController.text.trim(), 'location': locationController.text.trim(),
      'chef_type': selectedChefType, 'experience': int.tryParse(experienceController.text.trim()) ?? 0,
      'responsetime': selectedResponseTime, 'minnotice': selectedMinNotice,
      'teamsize': selectedTeamSize, 'bio': bioController.text.trim(),
      'is_active': true, 'rating': 0.0,
      'registration_date': DateTime.now().toIso8601String(), 'last_login': DateTime.now().toIso8601String(),
      'pricing': pricingData, 'equipment': equipmentJson, 'availability': availabilityJson,
      'languages': languagesJson, 'specialties': specialtiesJson,
      'certifications': certificationsJson, 'samplemenu': sampleMenuJson,
    };

    // --- API Call ---
    final String apiUrl = '$apibaseurl/rr/signup_chef';
    try {
      print("Sending data to $apiUrl...");
      final response = await http.post(Uri.parse(apiUrl), headers: {"Content-Type": "application/json"}, body: json.encode(chefData));

      print("API Response Status: ${response.statusCode}");

      if (response.statusCode == 201) {
        final responseData = json.decode(response.body);
        final int? chefID = responseData['ChefID'];
        final String? userType = responseData['UserType'];

        if (chefID != null && userType != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('ChefID', chefID);
          await prefs.setString('UserType', userType);
          print('Saved ChefID: $chefID, UserType: $userType');
        }

        _showSnackBar('Chef registration successful!', isError: false);
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ChefDash88new()));
      } else {
        String errorMessage = 'Failed to submit data.';
        try {
          final errorData = json.decode(response.body);
          errorMessage += ' Error: ${errorData['message'] ?? response.reasonPhrase}';
        } catch (_) {
          errorMessage += ' Status code: ${response.statusCode}';
        }
         _showSnackBar(errorMessage, isError: true);
      }
    } catch (error) {
      print("Submission Error: $error");
       _showSnackBar('An error occurred: $error', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

   // --- SnackBar Helper (Adapted) ---
  void _showSnackBar(String message, {bool isError = false, bool isWarning = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: whiteColor)),
        backgroundColor: isError ? errorColor : (isWarning ? Colors.orange[700] : accentTeal),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(15),
        duration: Duration(seconds: isError ? 4 : 3),
      ),
    );
  }


  // --- Build Method & UI Helpers ---

  // Consistent InputDecoration (Adapted from ChefSignUpPage)
  InputDecoration _buildInputDecoration(String label, {IconData? prefixIcon, Widget? suffixIcon, String? hintText}) {
     return InputDecoration(
          labelText: label,
          hintText: hintText,
          labelStyle: const TextStyle(color: primaryTeal, fontWeight: FontWeight.w500),
          hintStyle: const TextStyle(color: subtleTextColor, fontSize: 14),
          prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: primaryTeal, size: 20) : null,
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: textFieldFillColor, // Use consistent light fill
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: lightTeal, width: 1.0), // Default border
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: lightTeal, width: 1.0), // Border when enabled
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: primaryTeal, width: 1.5), // Border when focused
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: errorColor, width: 1.0), // Border on error
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: errorColor, width: 1.5), // Border on error + focused
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0), // Inner padding
          errorStyle: const TextStyle(color: errorColor, fontSize: 11) // Error text style
      );
  }

  // MultiSelect Dialog Field Helper (Use updated decoration)
  Widget _buildMultiSelectField({
    required String title,
    required List<String> allItems,
    required List<String> selectedItems,
    required Function(List<String>) onConfirm,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: MultiSelectDialogField(
        items: allItems.map((item) => MultiSelectItem(item, item)).toList(),
        title: title,
        decoration: _buildInputDecoration(title),
        buttonText: Text(
          selectedItems.isNotEmpty ? selectedItems.join(', ') : "Tap to select",
          style: TextStyle(
              color: selectedItems.isNotEmpty ? darkTeal : subtleTextColor,
              fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        onConfirm: onConfirm,
        buttonIcon: Icon(Icons.arrow_drop_down, color: primaryTeal),
        selectedColor: primaryTeal,
        dialogTextStyle: TextStyle(color: darkTeal),
        checkBoxCheckColor: whiteColor,
        checkBoxActiveColor: primaryTeal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: whiteColor,
      appBar: AppBar(
        title: Text('Chef Registration', style: TextStyle(color: whiteColor, fontWeight: FontWeight.bold)),
        backgroundColor: primaryTeal,
        elevation: 1.0,
        iconTheme: const IconThemeData(color: whiteColor),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16.0),
            children: <Widget>[
              _buildProfileImagePickerSection(),
              SizedBox(height: 24),
              _buildSectionCard( // <-- Using updated builder
                title: 'Personal Information', icon: Icons.person_outline,
                children: [
                  _buildNameField(), SizedBox(height: 16),
                  _buildEmailField(), SizedBox(height: 16),
                  _buildPhoneField(), SizedBox(height: 16),
                  GestureDetector(
                     onTap: _isFetchingLocation ? null : _getCurrentLocation,
                     child: AbsorbPointer(child: _buildLocationField()),
                  ),
                ],
              ),
              SizedBox(height: 24),
              _buildSectionCard( // <-- Using updated builder
                title: 'Account Credentials', icon: Icons.lock_outline,
                children: [
                  _buildPasswordField(), SizedBox(height: 16),
                  _buildConfirmPasswordField(),
                ],
              ),
              SizedBox(height: 24),
              _buildSectionCard( // <-- Using updated builder
                title: 'Chef Profile', icon: Icons.restaurant_menu,
                children: [
                  _buildChefTypeDropdown(), SizedBox(height: 16),
                  _buildExperienceField(), SizedBox(height: 16),
                  _buildBioField(),
                ],
              ),
              SizedBox(height: 24),
               _buildSectionCard( // <-- Using updated builder
                title: 'Pricing Structure', icon: Icons.monetization_on_outlined,
                children: [
                  _buildStartingPriceField(), SizedBox(height: 20),
                  _buildPerGigPricingSection(), SizedBox(height: 20),
                  _buildMonthlyPriceField(),
                ],
              ),
              SizedBox(height: 24),
              _buildSectionCard( // <-- Using updated builder
                title: 'Logistics & Availability', icon: Icons.timer_outlined,
                children: [
                  _buildResponseTimeDropdown(), SizedBox(height: 16),
                  _buildMinNoticeDropdown(), SizedBox(height: 16),
                  _buildTeamSizeDropdown(), SizedBox(height: 16),
                  _buildAvailabilitySelector(),
                ],
              ),
              SizedBox(height: 24),
              _buildSectionCard( // <-- Using updated builder
                title: 'Skills & Equipment', icon: Icons.build_circle_outlined,
                children: [
                  _buildLanguagesSelector(), SizedBox(height: 16),
                  _buildSpecialtiesSelector(), SizedBox(height: 16),
                  _buildCertificationsSelector(), SizedBox(height: 16),
                  _buildEquipmentSelector(),
                ],
              ),
              SizedBox(height: 24),
              _buildSectionCard( // <-- Using updated builder
                title: 'Samples', icon: Icons.photo_library_outlined,
                children: [
                  _buildSampleMenuImagesSection(),
                ],
              ),
              SizedBox(height: 30),
              _buildSubmitButton(),
              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // --- Reusable Section Card Widget (UPDATED with Border and Elevation Comment) ---
  Widget _buildSectionCard({required String title, required IconData icon, required List<Widget> children}) {
    return Card(
      // --- Card Elevation --- Adjust this value to change the shadow depth
      elevation: 1.0, // Current elevation is 2.0 (subtle shadow)
      margin: EdgeInsets.symmetric(vertical: 8.0),
      // --- Card Border --- Added border via shape property
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0), // Keep consistent rounding
        side: BorderSide( // Define the border
          color: lightTeal, // Use lightTeal for a subtle border
          width: 1.0,        // Set border width (adjust as needed)
        ),
      ),
      // --- End Card Border ---
      color: whiteColor, // Keep card background white
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: primaryTeal, size: 24.0),
                SizedBox(width: 10),
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkTeal)),
              ],
            ),
            Divider(height: 22, thickness: 0.1, color: lightTeal), // Lighter divider
            ...children,
          ],
        ),
      ),
    );
  }
  // --- End UPDATED _buildSectionCard ---


  // --- Individual Field/Section Builder Widgets (Apply consistent styling) ---

  // Profile Image Picker (Adapted from ChefSignUpPage)
  Widget _buildProfileImagePickerSection() {
     return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: lightTeal, width: 2),
                boxShadow: [ BoxShadow(color: Colors.grey.withOpacity(0.2), spreadRadius: 1, blurRadius: 4, offset: Offset(0, 2)) ]),
            child: CircleAvatar(
              radius: 60,
              backgroundColor: lighterTeal,
              backgroundImage: _profileImage != null ? FileImage(_profileImage!) : null,
              child: _profileImage == null && !_isUploadingProfileImage
                  ? Icon(Icons.add_a_photo, size: 50, color: primaryTeal)
                  : null,
            ),
          ),
          if (_isUploadingProfileImage)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                child: const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(whiteColor), strokeWidth: 3)),
              ),
            ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Material(
              color: primaryTeal, shape: const CircleBorder(), elevation: 3.0,
              child: InkWell(
                onTap: _isUploadingProfileImage ? null : pickProfileImage,
                customBorder: const CircleBorder(),
                splashColor: lightTeal.withOpacity(0.5),
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(Icons.edit, color: whiteColor, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Apply _buildInputDecoration to all TextFormField builders
  Widget _buildNameField() {
    return TextFormField(
      controller: nameController,
      decoration: _buildInputDecoration('Full Name / Business Name', prefixIcon: Icons.person),
      validator: (value) => value == null || value.isEmpty ? 'Please enter name' : null,
      style: TextStyle(color: darkTeal),
      textCapitalization: TextCapitalization.words,
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: emailController,
      decoration: _buildInputDecoration('Email Address', prefixIcon: Icons.email),
      keyboardType: TextInputType.emailAddress,
      validator: (value) {
        if (value == null || value.isEmpty) return 'Please enter an email';
        if (!RegExp(r'\S+@\S+\.\S+').hasMatch(value)) return 'Please enter a valid email';
        return null;
      },
      style: TextStyle(color: darkTeal),
    );
  }

  Widget _buildPhoneField() {
    return TextFormField(
      controller: phoneNumberController,
      decoration: _buildInputDecoration('Phone Number', prefixIcon: Icons.phone),
      keyboardType: TextInputType.phone,
      validator: (value) => value == null || value.isEmpty ? 'Please enter phone number' : null,
      style: TextStyle(color: darkTeal),
    );
  }

  // --- NEW Location Field Builder (Adapted from ChefSignUpPage) ---
  Widget _buildLocationField() {
    String currentHintText = _isFetchingLocation
        ? "Acquiring location${'.' * _locationHintDots}"
        : "Tap here or icon to get location";

    return AnimatedOpacity(
      opacity: _isFetchingLocation ? 0.7 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: TextFormField(
        controller: locationController,
        readOnly: true,
        style: const TextStyle(color: darkTeal, fontSize: 14),
        decoration: _buildInputDecoration(
            "Your Location",
            prefixIcon: Icons.location_on_outlined,
            hintText: currentHintText
        ).copyWith(
           suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: IconButton(
                icon: _isFetchingLocation
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.0, color: primaryTeal))
                    : const Icon(Icons.my_location_rounded, color: accentTeal),
                tooltip: 'Get Current Location',
                onPressed: _isFetchingLocation ? null : _getCurrentLocation,
              ),
            ),
            hintStyle: const TextStyle(color: subtleTextColor, fontStyle: FontStyle.italic, fontSize: 14),
        ),
        validator: (_) {
          if (locationController.text.isEmpty && !_isFetchingLocation) {
             return 'Please acquire your location';
          }
           if (locationController.text.startsWith('Failed to get location')) {
             return 'Location fetch failed, please try again';
          }
          return null;
        },
      ),
    );
  }


  Widget _buildPasswordField() {
    return TextFormField(
      controller: passwordController,
      decoration: _buildInputDecoration(
        'Password', prefixIcon: Icons.lock,
        suffixIcon: IconButton(
          icon: Icon(_passwordVisible ? Icons.visibility : Icons.visibility_off, color: primaryTeal),
          onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
        ),
      ),
      obscureText: !_passwordVisible,
      validator: (value) => value == null || value.length < 6 ? 'Password must be at least 6 characters' : null,
      style: TextStyle(color: darkTeal),
    );
  }

  Widget _buildConfirmPasswordField() {
    return TextFormField(
      controller: confirmPasswordController,
      decoration: _buildInputDecoration(
        'Confirm Password', prefixIcon: Icons.lock_reset_outlined,
        suffixIcon: IconButton(
          icon: Icon(_confirmPasswordVisible ? Icons.visibility : Icons.visibility_off, color: primaryTeal),
          onPressed: () => setState(() => _confirmPasswordVisible = !_confirmPasswordVisible),
        ),
      ),
      obscureText: !_confirmPasswordVisible,
      validator: (value) {
        if (value == null || value.isEmpty) return 'Please confirm password';
        if (value != passwordController.text) return 'Passwords do not match';
        return null;
      },
      style: TextStyle(color: darkTeal),
    );
  }

  // Apply style to DropdownButtonFormField builders
  Widget _buildChefTypeDropdown() {
    return DropdownButtonFormField<String>(
      value: selectedChefType,
      decoration: _buildInputDecoration('I am registering as a:', prefixIcon: Icons.business_center_outlined),
      onChanged: (newValue) {
        if (newValue != null && newValue != selectedChefType) {
          setState(() {
            selectedChefType = newValue;
            if (newValue == 'Individual') {
              final key50plus = perGigCategoryKeys['50+ people']!;
              final key100plus = perGigCategoryKeys['100+ people']!;
              perGigPriceControllers[key50plus]?.clear();
              perGigPriceControllers[key100plus]?.clear();
            }
          });
        }
      },
      items: chefTypes.map((String type) {
        return DropdownMenuItem<String>(value: type, child: Text(type, style: TextStyle(color: darkTeal)));
      }).toList(),
      style: TextStyle(color: darkTeal, fontSize: 16),
      iconEnabledColor: primaryTeal,
      validator: (value) => value == null ? 'Please select registration type' : null,
    );
  }

  Widget _buildExperienceField() {
    return TextFormField(
      controller: experienceController,
      decoration: _buildInputDecoration('Experience (Years)', prefixIcon: Icons.star_border),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: (value) {
        if (value == null || value.isEmpty) return 'Enter years of experience';
        if (int.tryParse(value) == null) return 'Enter a valid whole number';
        return null;
      },
      style: TextStyle(color: darkTeal),
    );
  }

  Widget _buildBioField() {
    return TextFormField(
      controller: bioController,
      decoration: _buildInputDecoration('Short Bio', prefixIcon: Icons.info_outline)
          .copyWith(hintText: 'Tell clients about yourself...'),
      maxLines: 4,
      validator: (value) => value == null || value.isEmpty ? 'Please enter a short bio' : null,
      style: TextStyle(color: darkTeal),
      textCapitalization: TextCapitalization.sentences,
    );
  }

   Widget _buildStartingPriceField() {
    return TextFormField(
      controller: startingPriceController,
      decoration: _buildInputDecoration('Starting Price (Optional)', prefixIcon: Icons.price_check, hintText: "e.g., Base price"),
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [ FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')) ],
      validator: (value) {
        if (value != null && value.isNotEmpty && double.tryParse(value) == null) return 'Enter a valid number';
        return null;
      },
      style: TextStyle(color: darkTeal),
    );
  }

  Widget _buildPerGigPricingSection() {
     return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("Per Gig Pricing (Optional)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: darkTeal)),
      SizedBox(height: 4),
      Text("Enter price based on number of guests:", style: TextStyle(fontSize: 14, color: subtleTextColor)),
      SizedBox(height: 12),
      Column(children: perGigCategories.map((category) {
        final controllerKey = perGigCategoryKeys[category]!;
        final bool isLargeGroupCategory = category == '50+ people' || category == '100+ people';
        final bool isEnabled = !isLargeGroupCategory || selectedChefType == 'Company';

        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(flex: 2, child: Text(category, style: TextStyle(color: isEnabled ? darkTeal : subtleTextColor, fontSize: 15))),
            SizedBox(width: 10),
            Expanded( flex: 3,
              child: TextFormField(
                controller: perGigPriceControllers[controllerKey],
                enabled: isEnabled,
                decoration: _buildInputDecoration("Price", prefixIcon: Icons.attach_money)
                    .copyWith(
                       contentPadding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 12.0),
                       labelText: null,
                       fillColor: isEnabled ? textFieldFillColor : disabledColor.withOpacity(0.2),
                       hintText: !isEnabled ? 'Company only' : null,
                       hintStyle: TextStyle(fontSize: 13, color: subtleTextColor),
                     ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [ FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')) ],
                validator: (value) {
                  if (isEnabled && value != null && value.isNotEmpty && double.tryParse(value) == null) return 'Invalid';
                  return null;
                },
                style: TextStyle(color: isEnabled ? darkTeal : subtleTextColor),
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
      decoration: _buildInputDecoration('Fixed Monthly Price (Optional)', prefixIcon: Icons.calendar_today_outlined, hintText: "e.g., For retainer services"),
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [ FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')) ],
      validator: (value) {
        if (value != null && value.isNotEmpty && double.tryParse(value) == null) return 'Enter a valid number';
        return null;
      },
      style: TextStyle(color: darkTeal),
    );
  }

  Widget _buildResponseTimeDropdown() {
     return DropdownButtonFormField<String>(
      value: selectedResponseTime,
      decoration: _buildInputDecoration('Typical Response Time', prefixIcon: Icons.reply),
      onChanged: (newValue) { if (newValue != null) setState(() => selectedResponseTime = newValue); },
      items: responseTimes.map((time) => DropdownMenuItem(value: time, child: Text(time, style: TextStyle(color: darkTeal)))).toList(),
      style: TextStyle(color: darkTeal, fontSize: 16), iconEnabledColor: primaryTeal,
      validator: (value) => value == null ? 'Select response time' : null,
    );
  }

  Widget _buildMinNoticeDropdown() {
     return DropdownButtonFormField<String>(
      value: selectedMinNotice,
      decoration: _buildInputDecoration('Minimum Booking Notice', prefixIcon: Icons.event_available),
      onChanged: (newValue) { if (newValue != null) setState(() => selectedMinNotice = newValue); },
      items: minNoticeOptions.map((notice) => DropdownMenuItem(value: notice, child: Text(notice, style: TextStyle(color: darkTeal)))).toList(),
      style: TextStyle(color: darkTeal, fontSize: 16), iconEnabledColor: primaryTeal,
      validator: (value) => value == null ? 'Select minimum notice' : null,
    );
  }

  Widget _buildTeamSizeDropdown() {
    return DropdownButtonFormField<String>(
      value: selectedTeamSize,
      decoration: _buildInputDecoration('Team Size', prefixIcon: Icons.people_outline),
      onChanged: (newValue) { if (newValue != null) setState(() => selectedTeamSize = newValue); },
      items: teamSizes.map((size) => DropdownMenuItem(value: size, child: Text(size, style: TextStyle(color: darkTeal)))).toList(),
      style: TextStyle(color: darkTeal, fontSize: 16), iconEnabledColor: primaryTeal,
      validator: (value) => value == null ? 'Select team size' : null,
    );
  }

  // MultiSelect fields will use the updated _buildMultiSelectField which uses _buildInputDecoration
  Widget _buildAvailabilitySelector() { return _buildMultiSelectField( title: 'Availability', allItems: allAvailability, selectedItems: availability, onConfirm: (values) => setState(() => availability = values) ); }
  Widget _buildLanguagesSelector() { return _buildMultiSelectField( title: 'Languages Spoken', allItems: allLanguages, selectedItems: languages, onConfirm: (values) => setState(() => languages = values) ); }
  Widget _buildSpecialtiesSelector() { return _buildMultiSelectField( title: 'Cuisine Specialties', allItems: allSpecialties, selectedItems: specialties, onConfirm: (values) => setState(() => specialties = values) ); }
  Widget _buildCertificationsSelector() { return _buildMultiSelectField( title: 'Certifications', allItems: allCertifications, selectedItems: certifications, onConfirm: (values) => setState(() => certifications = values) ); }
  Widget _buildEquipmentSelector() { return _buildMultiSelectField( title: 'Equipment Provided', allItems: allEquipment, selectedItems: equipment, onConfirm: (values) => setState(() => equipment = values) ); }

  // Style the sample menu images section
  Widget _buildSampleMenuImagesSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("Upload up to 3 sample menu images:", style: TextStyle(color: darkTeal, fontSize: 15)),
      SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(3, (index) {
          return _buildImagePickerSlot(
            index: index, imageFile: _sampleImages[index], imageUrl: _sampleImageUrls[index],
            isLoading: _isUploadingSample[index], onTap: () => pickSampleImage(index),
          );
        }),
      ),
    ]);
  }

  Widget _buildImagePickerSlot({required int index, required File? imageFile, required String? imageUrl, required bool isLoading, required VoidCallback onTap}) {
     return Column(children: [
      GestureDetector(
        onTap: isLoading ? null : onTap,
        child: Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: textFieldFillColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: lightTeal),
            image: imageFile != null ? DecorationImage(image: FileImage(imageFile), fit: BoxFit.cover) : null,
          ),
          child: Stack(alignment: Alignment.center, children: [
            if (imageFile == null && !isLoading) Icon(Icons.add_photo_alternate_outlined, color: primaryTeal, size: 30),
            if (isLoading) CircularProgressIndicator(strokeWidth: 2, color: primaryTeal),
            if (!isLoading && imageUrl != null)
              Positioned( top: 4, right: 4,
                child: CircleAvatar(radius: 10, backgroundColor: accentTeal, child: Icon(Icons.check, size: 14, color: whiteColor))),
          ]),
        ),
      ),
      SizedBox(height: 4),
      Text("Image ${index + 1}", style: TextStyle(fontSize: 12, color: subtleTextColor))
    ]);
  }

  // Submit Button (Adapted from ChefSignUpPage)
  Widget _buildSubmitButton() {
    final bool isDisabled = _isLoading || _isUploadingProfileImage || _isUploadingSample.any((uploading) => uploading);

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isDisabled ? null : submitData,
        style: ElevatedButton.styleFrom(
          backgroundColor: accentTeal,
          foregroundColor: whiteColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: isDisabled ? 0 : 2,
          disabledBackgroundColor: disabledColor.withOpacity(0.6),
          disabledForegroundColor: whiteColor.withOpacity(0.8),
        ),
        child: _isLoading
            ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(whiteColor)))
            : const Text('Register as Chef', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }

} // End of _ChefSignUpPageBetterNewState


// --- MultiSelect Dialog Widgets ---
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
    return InkWell(
      onTap: () async {
        List<String> currentSelection = [];
        if (buttonText is Text) {
          final text = (buttonText as Text).data ?? "";
          if (!text.startsWith("Tap to select")) {
             currentSelection = text.split(', ').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
          }
        }
        List<String> currentValues = items.where((item) => currentSelection.contains(item.label)).map((item) => item.value).toList();

        final selectedValues = await showDialog<List<String>>(
          context: context,
          builder: (BuildContext context) {
            return MultiSelectDialog(
              items: items,
              title: title,
              initialSelectedValues: currentValues,
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
        decoration: decoration.copyWith(
          contentPadding: EdgeInsets.fromLTRB(12, 10, 12, 10)
        ),
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
  late Set<String> selectedItems;

  @override
  void initState() {
    super.initState();
    selectedItems = Set<String>.from(widget.initialSelectedValues ?? {});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
      title: Text(widget.title, style: TextStyle(color: darkTeal, fontWeight: FontWeight.bold)),
      contentPadding: EdgeInsets.only(top: 12.0),
      content: Container(
        width: double.maxFinite,
        child: ListView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
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
              controlAffinity: ListTileControlAffinity.leading,
            );
          },
        ),
      ),
      actions: [
        TextButton(
            child: Text('Cancel', style: TextStyle(color: subtleTextColor)),
            onPressed: () => Navigator.pop(context)),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: widget.selectedColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0))),
          child: Text('Ok', style: TextStyle(color: whiteColor)),
          onPressed: () => Navigator.pop(context, selectedItems.toList()),
        ),
      ],
    );
  }
}

class MultiSelectItem {
  final String label;
  final String value;
  MultiSelectItem(this.label, this.value);
}