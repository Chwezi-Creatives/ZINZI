//cspell:disable
// lib/platform_info_stub.dart

// On web, these are not directly applicable in the same way.
// You might use kIsWeb or other web-specific checks.
String getOperatingSystem() {
  return "web"; // Or throw, or return a sensible default
}

bool isIOS() {
  return false;
}

bool isAndroid() {
  return false;
}