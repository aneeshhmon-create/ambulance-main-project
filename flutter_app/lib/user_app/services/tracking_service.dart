// lib/user_app/services/tracking_service.dart
//
// Fetches the live tracking data for the signed-in user's incident:
// GET /incidents/{id}/tracking (needs the user's Bearer token).

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:ambulance_app/user_app/config/api_config.dart';
import 'package:ambulance_app/user_app/models/tracking.dart';
import 'package:ambulance_app/user_app/services/auth_service.dart';

/// Thrown by [TrackingService]. [statusCode] is the HTTP status when the
/// server answered (401 = signed out, 403/404 = incident not available).
class TrackingException implements Exception {
  final String message;
  final int? statusCode;

  const TrackingException(this.message, {this.statusCode});

  bool get isUnauthorized => statusCode == 401;
  bool get isUnavailable => statusCode == 403 || statusCode == 404;

  @override
  String toString() => message;
}

class TrackingService {
  TrackingService({http.Client? client, UserAuthService? auth})
      : _client = client ?? http.Client(),
        _auth = auth ?? UserAuthService();

  static const Duration _timeout = Duration(seconds: 6);

  final http.Client _client;
  final UserAuthService _auth;

  Future<IncidentTracking> fetch(int incidentId) async {
    final token = await _auth.getToken();
    if (token == null) {
      throw const TrackingException('Please sign in again.', statusCode: 401);
    }
    final uri = Uri.parse('${ApiConfig.baseUrl}/incidents/$incidentId/tracking');
    try {
      final resp = await _client
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(_timeout);
      if (resp.statusCode == 401) {
        throw const TrackingException('Your session has expired.',
            statusCode: 401);
      }
      if (resp.statusCode == 403 || resp.statusCode == 404) {
        throw TrackingException(
          _detail(resp) ?? 'This incident is not available.',
          statusCode: resp.statusCode,
        );
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw TrackingException('Server error ${resp.statusCode}.',
            statusCode: resp.statusCode);
      }
      return IncidentTracking.fromJson(
          jsonDecode(resp.body) as Map<String, dynamic>);
    } on TrackingException {
      rethrow;
    } on TimeoutException {
      throw const TrackingException('Request timed out.');
    } catch (e) {
      throw TrackingException('Could not reach the server: $e');
    }
  }

  static String? _detail(http.Response r) {
    try {
      return (jsonDecode(r.body) as Map<String, dynamic>)['detail'] as String?;
    } catch (_) {
      return null;
    }
  }
}
