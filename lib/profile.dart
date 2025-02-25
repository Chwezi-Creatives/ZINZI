import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:zinzi2/reco.dart';
import 'package:zinzi2/useranalytics.dart';
import 'package:zinzi2/cart.dart';
import 'package:zinzi2/blogview.dart';
import 'package:image_picker/image_picker.dart';

final apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';

class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  int? _userId;
  Map<String, dynamic> _userMetrics = {};
  Map<String, dynamic> _userPreferences = {};
  bool _isLoading = true;
  String? _profileImage;
  TextEditingController _weightController = TextEditingController();
  bool _isEditingWeight = false;

  @override
  void initState() {
    super.initState();
    _loadUserId();
    _loadImageFromPrefs();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userId = prefs.getInt('user_id');
    });

    if (_userId != null) {
      await _fetchData();
    } else {
      _showSnackBar('User not logged in.');
    }
  }

  Future<void> _fetchData() async {
    try {
      await _fetchMetrics();
      await _fetchPreferences();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchMetrics() async {
    final url = '$apibaseurl/rr/get_user_metrics?user_id=$_userId';
    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData is Map<String, dynamic>) {
          setState(() {
            _userMetrics = responseData;
          });
        }
      } else {
        setState(() {
          _userMetrics = {
            'height': 'N/A',
            'weight': 'N/A',
            'bmi': 'N/A',
          };
        });
      }
    } catch (error) {
      _showSnackBar('Error fetching metrics: $error');
    }
  }

  Future<void> _fetchPreferences() async {
    final url = '$apibaseurl/rr/fetch_user_preferences?user_id=$_userId';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData is Map<String, dynamic>) {
          setState(() {
            _userPreferences = responseData; // Map the entire JSON response
          });
        }
      } else {
        _showSnackBar('Failed to fetch preferences.');
      }
    } catch (error) {
      _showSnackBar('Error fetching preferences: $error');
    }
  }

  Future<void> _pickImage() async {
    final imagePicker = ImagePicker();
    final pickedFile = await imagePicker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _profileImage = pickedFile.path;
      });
      _saveImageToPrefs(pickedFile.path);
    }
  }

  Future<void> _saveImageToPrefs(String imagePath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_image', imagePath);
  }

  Future<void> _loadImageFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _profileImage = prefs.getString('profile_image');
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _updateWeight() async {
    setState(() {
      _isEditingWeight = true;
    });
  }

  Future<void> _saveWeight() async {
    try {
      double newWeight = double.parse(_weightController.text);
      setState(() {
        _userMetrics['weight'] = newWeight;
        _isEditingWeight = false;
      });
      _showSnackBar('Weight updated successfully!');
    } catch (e) {
      _showSnackBar('Invalid weight input. Please enter a number.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile', textAlign: TextAlign.center),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      drawer: _buildDrawer(context),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/soft.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProfileHeader(),
                    const SizedBox(height: 24),
                    // Commenting out the User Information Card
                    // _buildUserInfoCard(),
                    const SizedBox(height: 1),
                    _buildPreferencesCard(),
                    const SizedBox(height: 1),
                    _buildMetricsCard(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: CircleAvatar(
              radius: 60,
              backgroundImage: _profileImage != null
                  ? FileImage(File(_profileImage!)) as ImageProvider<Object>?
                  : const AssetImage('assets/images/proffr.png'),
              child: _profileImage == null
                  ? const Icon(Icons.camera_alt,
                      size: 30, color: Colors.teal)
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _userPreferences['username'] ?? 'POA',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            _userPreferences['email'] ?? 'N/A',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // Widget _buildUserInfoCard() {
  //   return Card(
  //     color: Colors.teal[50],
  //     child: Padding(
  //       padding: const EdgeInsets.all(20.0),
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           Text(
  //             'User Information',
  //             style: TextStyle(
  //               fontSize: 24,
  //               fontWeight: FontWeight.bold,
  //               color: Colors.teal[800],
  //             ),
  //           ),
  //           _buildInfoRow('Username', _userPreferences['username'] ?? 'N/A',
  //               icon: Icons.person),
  //           _buildInfoRow('Email', _userPreferences['email'] ?? 'N/A',
  //               icon: Icons.email),
  //           _buildInfoRow('Gender', _userPreferences['gender'] ?? 'N/A',
  //               icon: Icons.wc),
  //           _buildInfoRow('Age', _userPreferences['age']?.toString() ?? 'N/A',
  //               icon: Icons.cake),
  //           SizedBox(height: 16),
  //           Center(
  //             child: SizedBox(
  //               width: 250,
  //               child: ElevatedButton(
  //                 onPressed: () {
  //                   Navigator.push(
  //                     context,
  //                     MaterialPageRoute(
  //                         builder: (context) => UserAnalyticsDashboard()),
  //                   );
  //                 },
  //                 style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
  //                 child: const Text('View Analytics',
  //                     style: TextStyle(color: Colors.white)),
  //               ),
  //             ),
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  Widget _buildPreferencesCard() {
    return Card(
      color: Colors.teal[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Preferences',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.teal[800],
              ),
            ),
            _buildInfoRow('Goals', _userPreferences['goals'] ?? 'N/A',
                icon: Icons.flag),
            _buildInfoRow('Diet Type', _userPreferences['diet_type'] ?? 'N/A',
                icon: Icons.restaurant_menu),
            _buildInfoRow('Food Restrictions', _userPreferences['food_restrictions'] ?? 'N/A',
                icon: Icons.warning),
            SizedBox(height: 16),
            Center(
              child: SizedBox(
                width: 250,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => RecommendedMealsScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  child: const Text('See Recommended Meals',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsCard() {
    return Card(
      color: Colors.teal[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Metrics',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.teal[800],
              ),
            ),
            _buildInfoRow(
                'Height', _userMetrics['height']?.toString() ?? 'N/A',
                icon: Icons.height),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '  Weight',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                _isEditingWeight
                    ? SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _weightController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: ' Weight',
                          ),
                        ),
                      )
                    : Text(_userMetrics['weight']?.toString() ?? 'N/A'),
              ],
            ),
            _buildInfoRow('BMI', _userMetrics['bmi']?.toString() ?? 'N/A',
                icon: Icons.accessibility),
            SizedBox(height: 16),
            Center(
              child: SizedBox(
                width: 250,
                child: ElevatedButton(
                  onPressed: () {
                    if (_isEditingWeight) {
                      _saveWeight();
                    } else {
                      _weightController.text =
                          _userMetrics['weight']?.toString() ?? '';
                      _updateWeight();
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  child: Text(_isEditingWeight ? 'Save' : 'Update Weight',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (icon != null)
                Icon(
                  icon,
                  color: Colors.teal[800],
                ),
              SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Text(value),
        ],
      ),
    );
  }

  //  DRAWER
  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: Container(
        color: Colors.teal[100],
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Colors.teal[600]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundImage: _profileImage != null
                            ? FileImage(File(_profileImage!))
                                as ImageProvider<Object>?
                            : const AssetImage('assets/images/proffr.png'),
                      ),
                      SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _userPreferences['username'] ?? 'POA',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _userPreferences['email'] ?? 'N/A',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: Icon(Icons.person, color: Colors.teal[800]),
                    title: Text('Profile',
                        style: TextStyle(color: Colors.teal[900])),
                    onTap: () {
                      Navigator.pop(context);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.analytics, color: Colors.teal[800]),
                    title: Text('Analytics Dashboard',
                        style: TextStyle(color: Colors.teal[900])),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => UserAnalyticsDashboard()),
                      );
                    },
                  ),
                  Divider(),
                  ListTile(
                    leading: Icon(Icons.shopping_cart, color: Colors.teal[800]),
                    title: Text('Shopping Cart',
                        style: TextStyle(color: Colors.teal[900])),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => ShoppingCartScreen()),
                      );
                    },
                  ),
                  Divider(),
                  ListTile(
                    leading: Icon(Icons.article, color: Colors.teal[800]),
                    title: Text('Blog',
                        style: TextStyle(color: Colors.teal[900])),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => BlogScreen(
                              url: 'https://artchwezi.blogspot.com/'),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading:
                        Icon(Icons.health_and_safety, color: Colors.teal[800]),
                    title: Text('Wellness Communities',
                        style: TextStyle(color: Colors.teal[900])),
                    onTap: () {
                      Navigator.pop(context);
                      // Navigate to Wellness Communities screen
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.help, color: Colors.teal[800]),
                    title: Text('Help',
                        style: TextStyle(color: Colors.teal[900])),
                    onTap: () {
                      Navigator.pop(context);
                      // Navigate to Help screen
                    },
                  ),
                ],
              ),
            ),
            Container(
              color: Colors.teal[100],
              height: 60,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Text(
                  '',
                  style: TextStyle(
                    color: Colors.teal[800],
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}