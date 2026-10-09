// lib/ambulance_app/services/ambulance_service.dart
//
// HTTP client for pushing ambulance GPS location to the backend.
// Keeps the driver screen free of network plumbing.

import 'dart:convert';
import 'package:http/http.dart' as http;

// ---------------------------------------------------------------------------
// Change this to your backend's base URL (no trailing slash).
// ---------------------------------------------------------------------------
const String kAmbulanceBaseUrl = 'http://localhost:8000';

class AmbulanceService {
  /// Sends a PATCH request to /ambulances/{ambulanceId}/location with the
  /// current GPS coordinates.
  ///
  /// Throws a [String] error message on failure (non-2xx or network error).
  static Future<void> updateLocation({
    required String ambulanceId,
    required double lat,
    required double lng,
  }) async {
    final uri =
        Uri.parse('$kAmbulanceBaseUrl/ambulances/$ambulanceId/location');
    final response = await http
        .patch(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'location': {'lat': lat, 'lng': lng},
          }),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw 'Server responded ${response.statusCode}';
    }
  }
}
