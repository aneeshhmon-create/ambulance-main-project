import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

// ---------------------------------------------------------------------------
// Typed location model
// ---------------------------------------------------------------------------

class UserLocation {
  const UserLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  String toString() => 'UserLocation($latitude, $longitude)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserLocation &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;
}

// ---------------------------------------------------------------------------
// Typed exceptions
// ---------------------------------------------------------------------------

abstract class LocationException implements Exception {
  const LocationException(this.message);
  final String message;

  @override
  String toString() => message;
}

class LocationServiceDisabledException extends LocationException {
  const LocationServiceDisabledException([
    super.message = 'Location services are disabled on your device. Please turn on GPS.',
  ]);
}

class LocationPermissionDeniedException extends LocationException {
  const LocationPermissionDeniedException([
    super.message = 'Location permission was denied. Please allow location access to dispatch emergency services.',
  ]);
}

class LocationPermissionPermanentlyDeniedException extends LocationException {
  const LocationPermissionPermanentlyDeniedException([
    super.message = 'Location permission is permanently denied. Please enable it in App Settings.',
  ]);
}

class LocationTimeoutException extends LocationException {
  const LocationTimeoutException([
    super.message = 'Could not acquire GPS position in time. Please check your signal and retry.',
  ]);
}

// ---------------------------------------------------------------------------
// Abstract LocationService interface
// ---------------------------------------------------------------------------

abstract class LocationService {
  /// Fetches the user's current GPS location or throws a [LocationException].
  Future<UserLocation> getCurrentLocation();

  /// Opens the device settings screen to enable GPS.
  Future<bool> openLocationSettings();

  /// Opens the operating system app settings page for this app.
  Future<bool> openAppSettings();
}

// ---------------------------------------------------------------------------
// Concrete implementation using Geolocator
// ---------------------------------------------------------------------------

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<UserLocation> getCurrentLocation() async {
    // 1. Check if device location service is enabled
    debugPrint('>>> [LocationService] 1. Checking isLocationServiceEnabled...');
    final serviceEnabled = await Geolocator.isLocationServiceEnabled()
        .timeout(const Duration(seconds: 3), onTimeout: () => true);
    debugPrint('>>> [LocationService] 1. Location service enabled: $serviceEnabled');
    if (!serviceEnabled) {
      throw const LocationServiceDisabledException();
    }

    // 2. Check and request permission if needed
    debugPrint('>>> [LocationService] 2. Checking permission...');
    var permission = await Geolocator.checkPermission()
        .timeout(const Duration(seconds: 3), onTimeout: () => LocationPermission.whileInUse);
    debugPrint('>>> [LocationService] 2. Current permission: $permission');

    if (permission == LocationPermission.denied) {
      debugPrint('>>> [LocationService] Requesting permission...');
      permission = await Geolocator.requestPermission()
          .timeout(const Duration(seconds: 10), onTimeout: () => LocationPermission.denied);
      debugPrint('>>> [LocationService] Requested permission result: $permission');
      if (permission == LocationPermission.denied) {
        throw const LocationPermissionDeniedException();
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationPermissionPermanentlyDeniedException();
    }

    // 3. Fast path: check last known position first
    debugPrint('>>> [LocationService] 3. Checking getLastKnownPosition...');
    try {
      final lastKnown = await Geolocator.getLastKnownPosition().timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
      if (lastKnown != null) {
        debugPrint('>>> [LocationService] Fast fix found: ${lastKnown.latitude}, ${lastKnown.longitude}');
        return UserLocation(
          latitude: lastKnown.latitude,
          longitude: lastKnown.longitude,
        );
      }
    } catch (e) {
      debugPrint('>>> [LocationService] Error reading lastKnownPosition: $e');
    }

    // 4. Request fresh position with strict 5s timeout
    debugPrint('>>> [LocationService] 4. Requesting fresh position...');
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 5));

      debugPrint('>>> [LocationService] Fresh fix acquired: ${pos.latitude}, ${pos.longitude}');
      return UserLocation(latitude: pos.latitude, longitude: pos.longitude);
    } catch (e) {
      debugPrint('>>> [LocationService] Fresh fix failed or timed out: $e. Retrying balanced accuracy...');
      // Fallback: try balanced accuracy (Wi-Fi / Cell towers)
      try {
        final fallbackPos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
          ),
        ).timeout(const Duration(seconds: 5));

        debugPrint('>>> [LocationService] Balanced fix acquired: ${fallbackPos.latitude}, ${fallbackPos.longitude}');
        return UserLocation(
          latitude: fallbackPos.latitude,
          longitude: fallbackPos.longitude,
        );
      } catch (e2) {
        debugPrint('>>> [LocationService] All location methods failed: $e2');
        throw const LocationTimeoutException();
      }
    }
  }

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();
}
