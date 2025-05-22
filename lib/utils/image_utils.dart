import 'package:flutter/foundation.dart' show kIsWeb;

class ImageUtils {
  /// Processes image URLs, especially handling Google Drive URLs for web compatibility
  static String processImageUrl(String url) {
    if (url.isEmpty) return url;

    try {
      final uri = Uri.parse(url);
      String processedUrl = url;
      
      // Handle direct Google Drive links (format: https://drive.google.com/uc?export=view&id=...)
      if (uri.host == 'drive.google.com' && 
          uri.path == '/uc' && 
          uri.queryParameters['export'] == 'view' && 
          uri.queryParameters['id'] != null) {
        final fileId = uri.queryParameters['id']!;
        processedUrl = 'https://drive.google.com/thumbnail?id=$fileId&sz=w800';
      }
      // Handle viewable Google Drive links (format: https://drive.google.com/file/d/FILE_ID/view)
      else if (uri.host == 'drive.google.com' && 
               uri.pathSegments.length >= 4 && 
               uri.pathSegments[0] == 'file' && 
               uri.pathSegments[2] == 'view') {
        final fileId = uri.pathSegments[3];
        processedUrl = 'https://drive.google.com/thumbnail?id=$fileId&sz=w800';
      }
      // Handle Google Drive file/d/ format
      else if (uri.host == 'drive.google.com' && 
               uri.pathSegments.isNotEmpty && 
               uri.pathSegments[0] == 'file' && 
               uri.pathSegments[1] == 'd' && 
               uri.pathSegments.length >= 3) {
        final fileId = uri.pathSegments[2];
        processedUrl = 'https://drive.google.com/thumbnail?id=$fileId&sz=w800';
      }
      
      // For web platform only, add a CORS proxy for Google Drive images
      if (kIsWeb && uri.host == 'drive.google.com') {
        // Use a CORS proxy to bypass CORS restrictions
        return 'https://cors-anywhere.herokuapp.com/' + processedUrl;
      }
      
      // Return processed URL or original URL for non-Google Drive links
      return processedUrl;
    } catch (e) {
      print('Error processing image URL: $e');
      return url; // Return original URL on error
    }
  }
}
