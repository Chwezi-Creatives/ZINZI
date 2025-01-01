import 'dart:io';

class MyHttpOverrides extends HttpOverrides {
  final List<int> certificate;

  MyHttpOverrides(this.certificate);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    // Create a SecurityContext with custom trusted certificates
    final securityContext = SecurityContext(withTrustedRoots: true);
    try {
      securityContext.setTrustedCertificatesBytes(certificate);
    } catch (e) {
      print('Error setting trusted certificates: $e');
    }

    // Create an HttpClient using the customized SecurityContext
    final client = super.createHttpClient(securityContext);

    // Accept self-signed certificates
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
      print('Accepting self-signed certificate from $host:$port');
      return true;
    };

    return client;
  }
}
