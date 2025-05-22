// lib/platform_info_io.dart
import 'dart:io' as io;

String getOperatingSystem() {
  return io.Platform.operatingSystem;
}

bool isIOS() {
  return io.Platform.isIOS;
}

bool isAndroid() {
  return io.Platform.isAndroid;
}