import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'splash.dart'; // Assuming your splash screen is in the 'splash.dart' file
import 'http_overrides.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // This must come first

  // Load the self-signed certificate into the app
  final certBytes = await rootBundle.load('assets/images/selfsigned.crt');
  final cert = certBytes.buffer.asUint8List();

  // Set up the HTTP client with the certificate
  HttpOverrides.global = MyHttpOverrides(cert);

  // Run the app
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
      ),
      home: SplashScreen(), // Replace with your starting page
    );
  }
}
