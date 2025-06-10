//cspell:disable
// lib/platform_info.dart
export 'platform_info_stub.dart' // Default
    if (dart.library.io) 'platform_info_io.dart'; // For VM
