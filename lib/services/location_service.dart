//cspell:disable
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:async'; // For TimeoutException
import 'package:http/http.dart' as http;
import 'dart:convert'; // For json.decode

class LocationService {
  // Singleton pattern
  LocationService._privateConstructor();
  static final LocationService _instance = LocationService._privateConstructor();
  static LocationService get instance => _instance;

  final ValueNotifier<Position?> currentPositionNotifier = ValueNotifier(null);
  final ValueNotifier<String?> currentAddressNotifier = ValueNotifier(null);
  final ValueNotifier<bool> isLoadingNotifier = ValueNotifier(false);
  final ValueNotifier<String?> errorNotifier = ValueNotifier(null);
  String? _lastKnownCoordinates; // Store coordinates as string

  Position? get currentPosition => currentPositionNotifier.value;
  String? get currentAddress => currentAddressNotifier.value;
  bool get isLoading => isLoadingNotifier.value;
  String? get error => errorNotifier.value;
  
  /// Returns the full location string in format: "lat, lng, address" if available
  /// or just the coordinates if address is not available
  String? get fullLocationString {
    if (currentAddress != null && currentAddress!.isNotEmpty) {
      final coords = _lastKnownCoordinates ?? 
          (currentPosition != null 
              ? '${currentPosition!.latitude}, ${currentPosition!.longitude}'
              : null);
      // Format: "lat, lng, address"
      return coords != null ? '$coords, $currentAddress' : currentAddress;
    }
    return _lastKnownCoordinates ?? 
        (currentPosition != null 
            ? '${currentPosition!.latitude}, ${currentPosition!.longitude}'
            : null);
  }

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      errorNotifier.value = 'Location services are disabled. Please enable the services';
      debugPrint('[LocationService] ${errorNotifier.value}');
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        errorNotifier.value = 'Location permissions are denied';
        debugPrint('[LocationService] ${errorNotifier.value}');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      errorNotifier.value = 'Location permissions are permanently denied, we cannot request permissions.';
      debugPrint('[LocationService] ${errorNotifier.value}');
      return false;
    }
    errorNotifier.value = null; // Clear previous permission error
    return true;
  }

  Future<Position?> getCurrentPositionOnly() async {
    isLoadingNotifier.value = true;
    errorNotifier.value = null; // Clear previous general error
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) {
      isLoadingNotifier.value = false;
      // errorNotifier is set by _handleLocationPermission
      return null;
    }
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium).timeout(const Duration(seconds: 15)); // Added timeout
      currentPositionNotifier.value = position;
      _lastKnownCoordinates = '${position.latitude}, ${position.longitude}';
      debugPrint('[LocationService] Fetched position: $position');
      isLoadingNotifier.value = false;
      return position;
    } on TimeoutException {
      errorNotifier.value = "Getting location timed out.";
      debugPrint('[LocationService] Error getting position: TimeoutException');
      isLoadingNotifier.value = false;
      return null;
    } catch (e) {
      errorNotifier.value = "Error getting current location: ${e.toString()}";
      debugPrint('[LocationService] Error getting position: $e');
      isLoadingNotifier.value = false;
      return null;
    }
  }

  Future<String?> _fallbackGeocode(Position position) async {
    debugPrint('[LocationService] Trying fallback geocoding service...');
    final String apiUrl =
        'https://geocode.maps.co/reverse?lat=${position.latitude}&lon=${position.longitude}&format=json&addressdetails=1';
    
    try {
      final response = await http
          .get(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Try to construct a detailed address from components first
        if (data['address'] is Map) {
          final address = data['address'] as Map<String, dynamic>;
          final addressParts = [
            address['road'],
            address['neighbourhood'],
            address['suburb'],
            address['city'] ?? address['town'] ?? address['village'],
            address['state'],
            address['country']
          ].where((part) => part != null && part.toString().isNotEmpty).toList();
          
          if (addressParts.isNotEmpty) {
            final formattedAddress = addressParts.join(', ');
            debugPrint('[LocationService] Fallback geocoding successful with detailed address');
            return formattedAddress;
          }
        }
        
        // Fall back to display_name if detailed address construction fails
        final address = data['display_name']?.toString();
        if (address != null && address.isNotEmpty) {
          debugPrint('[LocationService] Fallback geocoding successful with display_name');
          return address;
        }
      }
      debugPrint('[LocationService] Fallback geocoding failed or returned no data');
    } catch (e) {
      debugPrint('[LocationService] Error in fallback geocoding: $e');
    }
    return null;
  }

  Future<String?> getAddressFromPosition(Position position) async {
    try {
      isLoadingNotifier.value = true;
      errorNotifier.value = null; // Clear previous geocoding error
      String? fetchedAddress;

      debugPrint('[LocationService] Attempting to geocode position: ${position.latitude}, ${position.longitude}');

      // First try: Native geocoding
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        ).timeout(const Duration(seconds: 10));

        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          // Construct a more robust address string, handling nulls for individual parts
          List<String?> addressParts = [
            place.street,
            place.subLocality,
            place.locality,
            place.postalCode,
            place.administrativeArea,
            place.country
          ];
          // Filter out null or empty strings and join
          fetchedAddress = addressParts.where((part) => part != null && part.isNotEmpty).join(', ');
          
          if (fetchedAddress.isNotEmpty) {
            currentAddressNotifier.value = fetchedAddress;
            debugPrint('[LocationService] Native geocoding successful: $fetchedAddress');
            return fetchedAddress;
          }
        }
        
        // If we get here, native geocoding failed or returned no address
        debugPrint('[LocationService] Native geocoding failed or returned no address, trying fallback...');
        
      } catch (e) {
        debugPrint('[LocationService] Error in native geocoding: $e');
      }

      // Second try: Fallback to geocode.maps.co
      try {
        final fallbackAddress = await _fallbackGeocode(position);
        if (fallbackAddress != null) {
          currentAddressNotifier.value = fallbackAddress;
          errorNotifier.value = null; // Clear any previous errors
          return fallbackAddress;
        }
      } catch (e) {
        debugPrint('[LocationService] Fallback geocoding also failed: $e');
      }

      // If we get here, both methods failed
      errorNotifier.value = "Could not determine address for this location.";
      currentAddressNotifier.value = null;
      return null;
    } finally {
      // Always ensure loading is set to false when done
      if (isLoadingNotifier.value) {
        isLoadingNotifier.value = false;
      }
    }
  }

  Future<void> fetchAndSetCurrentLocation({bool forceGeocode = false, bool updateAddressRegardless = false}) async {
    isLoadingNotifier.value = true;
    errorNotifier.value = null; // Clear previous errors at the start of a full fetch cycle
    debugPrint('[LocationService] Starting fetchAndSetCurrentLocation (forceGeocode: $forceGeocode, updateAddressRegardless: $updateAddressRegardless)');

    Position? position = await getCurrentPositionOnly(); 

    if (position != null) {
      if (forceGeocode || currentAddressNotifier.value == null || updateAddressRegardless) {
        debugPrint('[LocationService] Proceeding to geocode because forceGeocode=$forceGeocode, currentAddressIsNull=${currentAddressNotifier.value == null}, updateAddressRegardless=$updateAddressRegardless.');
        await getAddressFromPosition(position);
      } else {
        debugPrint('[LocationService] Skipping geocoding as current address exists and not forced/updateAddressRegardless.');
        isLoadingNotifier.value = false; // Ensure loading is off if geocoding is skipped
      }
    } else {
      debugPrint('[LocationService] Position was null, cannot geocode.');
      // errorNotifier would have been set by getCurrentPositionOnly
      // isLoadingNotifier is also set to false by getCurrentPositionOnly if position is null
    }
    // Final check for isLoading, though sub-methods should handle it.
    if (isLoadingNotifier.value && (position == null || (position !=null && !(forceGeocode || currentAddressNotifier.value == null || updateAddressRegardless)) ) ){
        // If still loading but shouldn't be (e.g. position null, or geocoding skipped)
        isLoadingNotifier.value = false;
        debugPrint('[LocationService] Final isLoading check: Set to false.');
    }
    debugPrint('[LocationService] Finished fetchAndSetCurrentLocation. Loading: ${isLoadingNotifier.value}, Position: ${currentPositionNotifier.value}, Address: ${currentAddressNotifier.value}');
  }
}