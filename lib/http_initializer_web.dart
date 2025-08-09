//cspell:disable
// lib/http_initializer_web.dart
import 'dart:html';
import 'dart:typed_data'; // For Uint8List
import 'package:flutter/foundation.dart';

// Initialize the custom client
void initializeHttpOverrides(Uint8List certificateBytes) {
  // For web, we don't need to do anything special with the certificate
  debugPrint('HTTP Overrides initialized (web platform) - handling self-signed certificate warnings');
  
  // Add a warning for self-signed certificates
  window.alert('Warning: This app is using a self-signed certificate for development.\n\n' +
      'This is only recommended for development purposes.\n\n' +
      'Click OK to continue.');
}