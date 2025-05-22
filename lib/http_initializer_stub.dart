// lib/http_initializer_stub.dart
import 'dart:typed_data'; // For Uint8List type signature consistency

// Stub implementation for web - does nothing related to HttpOverrides
void initializeHttpOverrides(Uint8List certificateBytes) {
  // No-op on web or platforms where dart:io is not available/used for this.
  print("HTTP Overrides setup skipped (stub implementation).");
}