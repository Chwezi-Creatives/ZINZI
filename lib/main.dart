import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'notifications/notification_provider.dart';
import '../app_drawer_unified.dart';
import 'http_overrides.dart';
import 'splash.dart';

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

  // Initialize drawer data
  await AppDrawer.initializeUserData();
  print("Drawer data initialized");

  runApp(MyApp());
  print("App started");
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Provider<NotificationProvider>(
      create: (_) => NotificationProvider(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.teal,
        ),
        home: SplashScreen(),
      ),
    );
  }
}
