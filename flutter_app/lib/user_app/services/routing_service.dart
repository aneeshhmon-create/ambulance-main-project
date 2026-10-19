// lib/user_app/services/routing_service.dart
//
// OSRM routing service for calculating driving routes between coordinates.
// Swappable routing provider using public OSRM demo server.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteResult {
  final List<LatLng> points;
  final double distanceKm;
  final double durationMinutes;
  final bool isFallback;

  const RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationMinutes,
    this.isFallback = false,
  });
}

class RoutingService {
  RoutingService._();

  static final _distanceCalculator = const Distance();

  /// Requests a driving route from [origin] to [destination] using OSRM.
  /// Falls back to a direct straight line if the request fails or times out.
  static Future<RouteResult> getRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    // OSRM expects {lng},{lat};{lng},{lat}
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${origin.longitude},${origin.latitude};'
      '${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=geojson',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final routes = data['routes'] as List<dynamic>?;

        if (routes != null && routes.isNotEmpty) {
          final firstRoute = routes[0] as Map<String, dynamic>;
          final geometry = firstRoute['geometry'] as Map<String, dynamic>;
          final coords = geometry['coordinates'] as List<dynamic>;

          final points = coords.map((c) {
            final coord = c as List<dynamic>;
            // GeoJSON coordinates are [lng, lat]
            final lng = (coord[0] as num).toDouble();
            final lat = (coord[1] as num).toDouble();
            return LatLng(lat, lng);
          }).toList();

          final distanceMeters = (firstRoute['distance'] as num).toDouble();
          final durationSeconds = (firstRoute['duration'] as num).toDouble();

          return RouteResult(
            points: points,
            distanceKm: distanceMeters / 1000.0,
            durationMinutes: durationSeconds / 60.0,
            isFallback: false,
          );
        }
      }
      debugPrint('[RoutingService] OSRM responded with status ${response.statusCode}');
    } catch (e) {
      debugPrint('[RoutingService] Route fetch failed, falling back to direct line: $e');
    }

    // Fallback straight line between origin and destination
    final directKm = _distanceCalculator.as(
      LengthUnit.Kilometer,
      origin,
      destination,
    );
    // Rough estimate: 40 km/h average emergency speed -> 1.5 min per km
    final estimatedMinutes = directKm * 1.5;

    return RouteResult(
      points: [origin, destination],
      distanceKm: directKm,
      durationMinutes: estimatedMinutes,
      isFallback: true,
    );
  }
}
