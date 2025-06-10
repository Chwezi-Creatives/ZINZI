//cspell:disable
// lib/http_initializer_io.dart
import 'dart:io';
import 'dart:typed_data'; // For Uint8List

// This class is only used on non-web platforms
class _MyHttpOverrides extends HttpOverrides {
  final Uint8List certificateBytes;

  _MyHttpOverrides(this.certificateBytes);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final securityContext = SecurityContext(withTrustedRoots: true);
    try {
      // Ensure you're adding the certificate correctly.
      // setTrustedCertificatesBytes expects a list of PEM or DER encoded certificates.
      // If your .crt file is a single PEM certificate, this should be okay.
      securityContext.setTrustedCertificatesBytes(certificateBytes);
    } catch (e) {
      print('Error setting trusted certificates: $e');
      // Potentially re-throw or handle more gracefully
    }

    final client = super.createHttpClient(securityContext);

    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
      // IMPORTANT: Only return true for specific hosts you trust.
      // Returning true for all self-signed certs is a security risk.
      // Example: if (host == 'your-self-signed-server.com') return true;
      print('Accepting self-signed certificate from $host:$port');
      return true; // Be very careful with this line in production
    };
    return client;
  }
}

void initializeHttpOverrides(Uint8List certificateBytes) {
  HttpOverrides.global = _MyHttpOverrides(certificateBytes);
  print("HTTP Overrides set (IO implementation).");
}