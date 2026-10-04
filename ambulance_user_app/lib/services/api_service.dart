import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/user.dart';

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
/// All methods share private [_get] and [_post] helpers.
///
/// The [client] constructor parameter accepts any [http.Client], making it
/// trivial to inject a mock in unit tests.
class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 5);

  /// Helper to extract detail message from error response if present.
  ApiException _parseErrorResponse(http.Response response) {
    try {
      final errorJson = jsonDecode(response.body);
      if (errorJson is Map<String, dynamic> && errorJson.containsKey('detail')) {
        final detail = errorJson['detail'];
        if (detail is String) {
          return ApiException(detail);
        } else if (detail is List && detail.isNotEmpty) {
          final first = detail.first;
          if (first is Map && first.containsKey('msg')) {
            return ApiException(first['msg'].toString());
          }
          return ApiException(detail.toString());
        }
      }
    } on FormatException {
      // Body is not JSON
    }

    return ApiException(
      'Server returned status ${response.statusCode}. Please try again later.',
    );
  }

  /// Generic GET helper used by public methods.
  Future<dynamic> _get(String path) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');

    try {
      final response = await _client.get(uri).timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _parseErrorResponse(response);
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
      rethrow;
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

  /// Generic POST helper used by public methods.
  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');

    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _parseErrorResponse(response);
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
      rethrow;
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
  Future<dynamic> checkHealth() => _get('/health');

  /// Calls POST /users to register or retrieve an existing user.
  Future<User> registerUser(String name, String phone) async {
    final data = await _post('/users', {
      'name': name,
      'phone': phone,
    });

    if (data is Map<String, dynamic>) {
      return User.fromJson(data);
    }
    throw const ApiException('Invalid response format received from server.');
  }
}
