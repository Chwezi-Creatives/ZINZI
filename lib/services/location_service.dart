import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationService {
  // Singleton pattern
  LocationService._privateConstructor();
  static final LocationService _instance = LocationService._privateConstructor();
  static LocationService get instance => _instance;

  final ValueNotifier<Position?> currentPositionNotifier = ValueNotifier(null);
  final ValueNotifier<String?> currentAddressNotifier = ValueNotifier(null);
  final ValueNotifier<bool> isLoadingNotifier = ValueNotifier(false);
  final ValueNotifier<String?> errorNotifier = ValueNotifier(null);

  Position? get currentPosition => currentPositionNotifier.value;
  String? get currentAddress => currentAddressNotifier.value;
  bool get isLoading => isLoadingNotifier.value;
  String? get error => errorNotifier.value;

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      errorNotifier.value = 'Location services are disabled. Please enable the services';
      debugPrint(errorNotifier.value);
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        errorNotifier.value = 'Location permissions are denied';
        debugPrint(errorNotifier.value);
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      errorNotifier.value = 'Location permissions are permanently denied, we cannot request permissions.';
      debugPrint(errorNotifier.value);
      return false;
    }
    errorNotifier.value = null; // Clear previous error
    return true;
  }

  Future<Position?> getCurrentPositionOnly() async {
    isLoadingNotifier.value = true;
    errorNotifier.value = null;
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) {
      isLoadingNotifier.value = false;
      return null;
    }
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium); // Medium for faster acquisition
      currentPositionNotifier.value = position;
      debugPrint('[LocationService] Fetched position: $position');
      isLoadingNotifier.value = false;
      return position;
    } catch (e) {
      errorNotifier.value = "Error getting location: ${e.toString()}";
      debugPrint('[LocationService] Error getting position: $e');
      isLoadingNotifier.value = false;
      return null;
    }
  }

  Future<String?> getAddressFromPosition(Position position) async {
    isLoadingNotifier.value = true; // Indicate loading for geocoding
    errorNotifier.value = null;
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String address =
            "${place.street}, ${place.subLocality}, ${place.locality}, ${place.postalCode}, ${place.country}";
        currentAddressNotifier.value = address;
        debugPrint('[LocationService] Fetched address: $address');
        isLoadingNotifier.value = false;
        return address;
      } else {
        errorNotifier.value = "No address found for the coordinates.";
        debugPrint('[LocationService] No placemarks found.');
      }
    } catch (e) {
      errorNotifier.value = "Error getting address: ${e.toString()}";
      debugPrint('[LocationService] Error during geocoding: $e');
    }
    isLoadingNotifier.value = false;
    return null;
  }

  Future<void> fetchAndSetCurrentLocation({bool forceGeocode = false, bool updateAddressRegardless = false}) async {
    isLoadingNotifier.value = true;
    errorNotifier.value = null;
    debugPrint('[LocationService] Starting fetchAndSetCurrentLocation (forceGeocode: $forceGeocode, updateAddressRegardless: $updateAddressRegardless)');

    Position? position = await getCurrentPositionOnly(); // This already sets isLoading and positionNotifier

    if (position != null) {
      // Geocode if forced, or if no address is currently stored, or if updateAddressRegardless is true
      if (forceGeocode || currentAddressNotifier.value == null || updateAddressRegardless) {
        debugPrint('[LocationService] Proceeding to geocode.');
        await getAddressFromPosition(position);
      } else {
        debugPrint('[LocationService] Skipping geocoding as current address exists and not forced/updateAddressRegardless.');
      }
    } else {
      debugPrint('[LocationService] Position was null, cannot geocode.');
      // errorNotifier would have been set by getCurrentPositionOnly
    }
    // Ensure isLoadingNotifier is false at the end of the operation,
    // especially if geocoding was skipped.
    // getCurrentPositionOnly and getAddressFromPosition manage their own isLoading states.
    // If position is null, getCurrentPositionOnly would have set isLoading to false.
    // If position is not null AND geocoding was skipped, isLoading might still be true from the start of this method.
    if (position != null && !(forceGeocode || currentAddressNotifier.value == null || updateAddressRegardless)) {
        // This means position was fetched, but geocoding was skipped.
        // getCurrentPositionOnly would have set isLoading to false after fetching position.
        // So, isLoadingNotifier.value should already be false here.
        // We can add a final check to be safe.
        if (isLoadingNotifier.value) { // If it's somehow still true
             isLoadingNotifier.value = false;
             debugPrint('[LocationService] Set isLoading to false as geocoding was skipped.');
        }
    } else if (position == null && isLoadingNotifier.value) {
        // If position is null and isLoading is still true (should be handled by getCurrentPositionOnly)
        isLoadingNotifier.value = false;
        debugPrint('[LocationService] Set isLoading to false as position was null.');
    }
    // If geocoding happened, getAddressFromPosition sets isLoading to false.

    debugPrint('[LocationService] Finished fetchAndSetCurrentLocation. Loading: ${isLoadingNotifier.value}, Position: ${currentPositionNotifier.value}, Address: ${currentAddressNotifier.value}');
  }
}