import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// Thrown by [ApiService] when any request fails.
///
/// The [message] is always user-readable (no raw stack traces).
class ApiException implements Exception {
  const ApiException(this.message);
  final String message;

  @override
  String toString() => 'ApiException: $message';
}

/// Thin HTTP client wrapper around the FastAPI backend.
///
/// All methods share the private [_get] helper, so adding new endpoints later
/// (e.g. by Person C's screens) is one-liner: call `_get('/your/path')`.
///
/// The [client] constructor parameter accepts any [http.Client], making it
/// trivial to inject a mock in unit tests.
class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 5);

  /// Generic GET helper used by all public methods.
  ///
  /// Returns the decoded JSON body on HTTP 2xx.
  /// Maps every failure mode to a descriptive [ApiException].
  Future<dynamic> _get(String path) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');

    try {
      final response = await _client.get(uri).timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          'Server returned status ${response.statusCode}. '
          'Please try again later.',
        );
      }

      try {
        return jsonDecode(response.body);
      } on FormatException {
        throw const ApiException(
          'Unexpected response from server. '
          'The data could not be understood.',
        );
      }
    } on ApiException {
      rethrow; // already formatted
    } on SocketException {
      throw const ApiException(
        'No network connection. '
        'Check your Wi-Fi and try again.',
      );
    } on TimeoutException {
      throw const ApiException(
        'Request timed out. '
        'The server took too long to respond.',
      );
    } on Exception catch (e) {
      throw ApiException('Unexpected error: $e');
    }
  }

  /// Calls GET /health and returns the parsed JSON response body.
  ///
  /// Reused by any screen that needs to verify backend connectivity.
  Future<dynamic> checkHealth() => _get('/health');
}
