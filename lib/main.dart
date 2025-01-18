import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Import the dotenv package
import 'splash.dart'; // Assuming your splash screen is in the 'splash.dart' file
import 'http_overrides.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print("Initializing WidgetsBinding");

  await dotenv.load(fileName: ".env");
  print(".env file loaded");

  final certBytes = await rootBundle.load('assets/images/selfsigned.crt');
  print("Certificate loaded");

  final cert = certBytes.buffer.asUint8List();
  HttpOverrides.global = MyHttpOverrides(cert);
  print("HTTP Overrides set");

  runApp(MyApp());
  print("App started");
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
