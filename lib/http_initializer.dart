//cspell:disable
// lib/http_initializer.dart
export 'http_initializer_stub.dart' // Default, e.g., for web
    if (dart.library.io) 'http_initializer_io.dart'; // For mobile/desktop (VM)