import 'package:zinzi/services/location_service.dart';

/// Returns the current location as a formatted string "lat,lng" if available
String? getGeoFencedLocationParam() {
  final position = LocationService.instance.currentPosition;
  if (position != null) {
    // Format as "lat,lng" without spaces
    return '${position.latitude},${position.longitude}';
  }
  return null;
}
