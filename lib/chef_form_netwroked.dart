import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:zinzi2/chef_net.dart';
import 'package:geolocator/geolocator.dart'; // Import geolocator for location services

final apibaseurl = dotenv.env['API_BASE_URL-intranet'] ?? 'https://default.url';

class ChefDataFormNetwork extends StatefulWidget {
  @override
  _ChefDataFormNetworkState createState() => _ChefDataFormNetworkState();
}

class _ChefDataFormNetworkState extends State<ChefDataFormNetwork> {
  final _formKey = GlobalKey<FormState>();
  String name = '';
  String location = '';
  String imageUrl = '';
  double price = 0.0;
  int experience = 0;
  String equipment = '';
  String bio = '';
  List<String> languages = [];
  List<String> specialties = [];
  List<String> certifications = [];
  List<String> sampleMenu = [];
  List<String> availability = [];
  
  bool isLocationOptional = false; // New variable to track if location is optional

  // Predefined values
  final List<String> responseTimes = ["Immediate", "1 Hour", "2 Hours", "4 Hours"];
  final List<String> teamSizes = ["1", "2", "3", "4", "5", "6+", "10+"];
  final List<String> minNoticeOptions = ["1 Hour", "2 Hours", "4 Hours", "1 Day", "2 Days"];
  final List<String> allLanguages = ["English","Runyankole", "Rukiga","Luganda","Lusoga","Lugbala","Spanish", "French", "German", "Italian"];
  final List<String> allSpecialties = ["Luwombo","Katogo","Street food","Pastry","Culinary","Italian", "French", "Japanese", "Indian", "Vegetarian", "Vegan"];
  final List<String> allCertifications = ["Culinary Arts", "Food Safety", "Nutrition", "Pastry Arts"];
  final List<String> allAvailability = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

  String selectedResponseTime = 'Immediate';
  String selectedTeamSize = '1';
  String selectedMinNotice = '1 Hour';

  int _getMinNoticeValue(String selected) {
    switch (selected) {
      case "1 Hour":
        return 1;
      case "2 Hours":
        return 2;
      case "4 Hours":
        return 4;
      case "1 Day":
        return 24;
      case "2 Days":
        return 48;
      default:
        return 0;
    }
  }

  Future<void> submitData() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      final chefData = {
        'name': name,
        if (!isLocationOptional || location.isNotEmpty) 'location': location, // Include location based on the checkbox
        'image': imageUrl,
        'price': price,
        'experience': experience,
        'response_time': selectedResponseTime,
        'min_notice': _getMinNoticeValue(selectedMinNotice),
        'team_size': selectedTeamSize,
        'equipment': equipment,
        'bio': bio,
        'availability': availability,
        'languages': languages,
        'specialties': specialties,
        'certifications': certifications,
        'sample_menu': sampleMenu,
      };

      final String apiUrl = '$apibaseurl/rr/achefs';
      try {
        final response = await http.post(
          Uri.parse(apiUrl),
          headers: {"Content-Type": "application/json"},
          body: json.encode(chefData),
        );

        if (response.statusCode == 201) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Chef data submitted successfully!')),
          );
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => ChooseChefNetwork()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to submit data. Error: ${response.reasonPhrase}')),
          );
        }
      } catch (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An error occurred: $error')),
        );
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled;
      LocationPermission permission;

      // Check if location services are enabled
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return Future.error('Location services are disabled.');
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return Future.error('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return Future.error('Location permissions are permanently denied');
      }

      // When permissions are granted, get the current location
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        location = "${position.latitude}, ${position.longitude}"; // Format: "lat, long"
      });

    } catch (e) {
      print(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error getting location: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chef Registration', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.teal[800],
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/soft.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: ListView(
              children: <Widget>[
                TextFormField(
                  decoration: InputDecoration(labelText: 'Name', labelStyle: TextStyle(color: Colors.teal[400])),
                  onSaved: (value) => name = value!,
                  validator: (value) => value!.isEmpty ? 'Please enter a name' : null,
                  style: TextStyle(color: Colors.teal[900]),
                ),
                TextFormField(
                  readOnly: true, // Make it read-only
                  decoration: InputDecoration(
                    labelText: 'Location',
                    labelStyle: TextStyle(color: Colors.teal[400]),
                    suffixIcon: IconButton( // Button to get location
                      icon: Icon(Icons.location_on),
                      onPressed: isLocationOptional ? null : _getCurrentLocation, // Disable button if optional
                    ),
                  ),
                  onSaved: (value) => location = value!,
                  validator: (value) => isLocationOptional && value!.isEmpty ? 'Please select a location or uncheck the optional' : null,
                  style: TextStyle(color: Colors.teal[900]),
                  initialValue: location, // Set the initial value to the location if available
                ),
                // Checkbox to make location optional
                Row(
                  children: [
                    Checkbox(
                      value: isLocationOptional,
                      onChanged: (bool? value) {
                        setState(() {
                          isLocationOptional = value!;
                          if (isLocationOptional) {
                            location = ''; // Clear location if optional is selected
                          }
                        });
                      },
                    ),
                    Text(
                      'Location is optional',
                      style: TextStyle(color: Colors.teal[900]),
                    ),
                  ],
                ),
                TextFormField(
                  decoration: InputDecoration(labelText: 'Image URL', labelStyle: TextStyle(color: Colors.teal[400])),
                  onSaved: (value) => imageUrl = value!,
                  validator: (value) => value!.isEmpty ? 'Please enter an image URL' : null,
                  style: TextStyle(color: Colors.teal[900]),
                ),
                TextFormField(
                  decoration: InputDecoration(labelText: 'Price', labelStyle: TextStyle(color: Colors.teal[400])),
                  keyboardType: TextInputType.number,
                  onSaved: (value) => price = double.parse(value!),
                  validator: (value) => value!.isEmpty ? 'Please enter a price' : null,
                  style: TextStyle(color: Colors.teal[900]),
                ),
                TextFormField(
                  decoration: InputDecoration(labelText: 'Experience (Years)', labelStyle: TextStyle(color: Colors.teal[400])),
                  keyboardType: TextInputType.number,
                  onSaved: (value) => experience = int.parse(value!),
                  validator: (value) => value!.isEmpty ? 'Please enter experience in years' : null,
                  style: TextStyle(color: Colors.teal[900]),
                ),
                DropdownButtonFormField<String>(
                  value: selectedResponseTime,
                  decoration: InputDecoration(labelText: 'Response Time', labelStyle: TextStyle(color: Colors.teal[400])),
                  onChanged: (newValue) {
                    setState(() {
                      selectedResponseTime = newValue!;
                    });
                  },
                  items: responseTimes.map((String time) {
                    return DropdownMenuItem<String>(
                      value: time,
                      child: Text(time, style: TextStyle(color: Colors.teal[900])),
                    );
                  }).toList(),
                ),
                DropdownButtonFormField<String>(
                  value: selectedMinNotice,
                  decoration: InputDecoration(labelText: 'Minimum Notice', labelStyle: TextStyle(color: Colors.teal[400])),
                  onChanged: (newValue) {
                    setState(() {
                      selectedMinNotice = newValue!;
                    });
                  },
                  items: minNoticeOptions.map((String notice) {
                    return DropdownMenuItem<String>(
                      value: notice,
                      child: Text(notice, style: TextStyle(color: Colors.teal[900])),
                    );
                  }).toList(),
                ),
                DropdownButtonFormField<String>(
                  value: selectedTeamSize,
                  decoration: InputDecoration(labelText: 'Team Size', labelStyle: TextStyle(color: Colors.teal[400])),
                  onChanged: (newValue) {
                    setState(() {
                      selectedTeamSize = newValue!;
                    });
                  },
                  items: teamSizes.map((String size) {
                    return DropdownMenuItem<String>(
                      value: size,
                      child: Text(size, style: TextStyle(color: Colors.teal[900])),
                    );
                  }).toList(),
                ),
                TextFormField(
                  decoration: InputDecoration(labelText: 'Equipment', labelStyle: TextStyle(color: Colors.teal[400])),
                  onSaved: (value) => equipment = value!,
                  validator: (value) => value!.isEmpty ? 'Please specify equipment' : null,
                  style: TextStyle(color: Colors.teal[900]),
                ),
                TextFormField(
                  decoration: InputDecoration(labelText: 'Bio', labelStyle: TextStyle(color: Colors.teal[400])),
                  maxLines: 3,
                  onSaved: (value) => bio = value!,
                  validator: (value) => value!.isEmpty ? 'Please enter a bio' : null,
                  style: TextStyle(color: Colors.teal[900]),
                ),
                SizedBox(height: 16),
                MultiSelectDialogField(
                  items: allAvailability.map((day) => MultiSelectItem(day, day)).toList(),
                  title: "Availability",
                  buttonText: Text("Select Availability", style: TextStyle(color: Colors.teal[900])),
                  onConfirm: (values) {
                    setState(() {
                      availability = values.cast<String>();
                    });
                  },
                ),
                SizedBox(height: 16),
                MultiSelectDialogField(
                  items: allLanguages.map((language) => MultiSelectItem(language, language)).toList(),
                  title: "Languages",
                  buttonText: Text("Select Languages", style: TextStyle(color: Colors.teal[900])),
                  onConfirm: (values) {
                    setState(() {
                      languages = values.cast<String>();
                    });
                  },
                ),
                SizedBox(height: 16),
                MultiSelectDialogField(
                  items: allSpecialties.map((specialty) => MultiSelectItem(specialty, specialty)).toList(),
                  title: "Specialties",
                  buttonText: Text("Select Specialties", style: TextStyle(color: Colors.teal[900])),
                  onConfirm: (values) {
                    setState(() {
                      specialties = values.cast<String>();
                    });
                  },
                ),
                SizedBox(height: 16),
                MultiSelectDialogField(
                  items: allCertifications.map((certification) => MultiSelectItem(certification, certification)).toList(),
                  title: "Certifications",
                  buttonText: Text("Select Certifications", style: TextStyle(color: Colors.teal[900])),
                  onConfirm: (values) {
                    setState(() {
                      certifications = values.cast<String>();
                    });
                  },
                ),
                TextFormField(
                  decoration: InputDecoration(labelText: 'Sample Menu (comma separated)', labelStyle: TextStyle(color: Colors.teal[400])),
                  onSaved: (value) => sampleMenu = value!.split(',').map((e) => e.trim()).toList(),
                  validator: (value) => value!.isEmpty ? 'Please enter sample menu items' : null,
                  style: TextStyle(color: Colors.teal[900]),
                ),
                SizedBox(height: 20),
                ElevatedButton(
                  onPressed: submitData,
                  child: Text('Submit', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal[800]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MultiSelectDialogField extends StatelessWidget {
  final List<MultiSelectItem> items;
  final String title;
  final Widget buttonText;
  final Function(List<String>) onConfirm;

  MultiSelectDialogField({
    required this.items,
    required this.title,
    required this.buttonText,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final selectedValues = await showDialog<List<String>>(
          context: context,
          builder: (BuildContext context) {
            return MultiSelectDialog(
              items: items,
              title: title,
            );
          },
        );
        if (selectedValues != null) {
          onConfirm(selectedValues);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: title,
          labelStyle: TextStyle(color: Colors.teal[400]),
          border: OutlineInputBorder(),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: buttonText,
        ),
      ),
    );
  }
}

class MultiSelectDialog extends StatefulWidget {
  final String title;
  final List<MultiSelectItem> items;

  MultiSelectDialog({required this.title, required this.items});

  @override
  State<MultiSelectDialog> createState() => _MultiSelectDialogState();
}

class _MultiSelectDialogState extends State<MultiSelectDialog> {
  List<String> selectedItems = [];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, style: TextStyle(color: Colors.teal[900])),
      content: SingleChildScrollView(
        child: Column(
          children: widget.items.map((item) {
            return CheckboxListTile(
              title: Text(item.label, style: TextStyle(color: Colors.teal[900])),
              value: selectedItems.contains(item.value),
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    selectedItems.add(item.value);
                  } else {
                    selectedItems.remove(item.value);
                  }
                });
              },
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          child: Text('Cancel', style: TextStyle(color: Colors.teal[900])),
          onPressed: () => Navigator.pop(context),
        ),
        TextButton(
          child: Text('Ok', style: TextStyle(color: Colors.teal[900])),
          onPressed: () => Navigator.pop(context, selectedItems),
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