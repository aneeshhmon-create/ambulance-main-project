// lib/driver_app/services/auth_service.dart
//
// Handles Google sign-in, backend JWT exchange, secure token storage,
// and fetching the driver's linked ambulances.
//
// All network and storage calls go through this class so the UI stays free
// of network plumbing.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'package:ambulance_app/driver_app/config/api_config.dart';
import 'package:ambulance_app/driver_app/models/driver.dart';

// ── Storage keys ─────────────────────────────────────────────────────────────

const _kJwtKey = 'driver_jwt';
const _kDriverIdKey = 'driver_id';
const _kDriverNameKey = 'driver_name';
const _kDriverEmailKey = 'driver_email';
const _kDriverPhotoKey = 'driver_photo_url';
const _kAmbulanceIdKey = 'selected_ambulance_id';
const _kAmbulanceRegKey = 'selected_ambulance_reg';

// ── Exceptions ────────────────────────────────────────────────────────────────

class NotRegisteredDriverException implements Exception {
  final String message;
  const NotRegisteredDriverException(
      [this.message =
          'This Google account is not registered as a driver.']);
  @override
  String toString() => message;
}

class NetworkException implements Exception {
  final String message;
  const NetworkException([this.message = 'Network error. Check your connection.']);
  @override
  String toString() => message;
}

class ServerException implements Exception {
  final int statusCode;
  final String message;
  const ServerException(this.statusCode, this.message);
  @override
  String toString() => 'Server error $statusCode: $message';
}

// ── AuthService ───────────────────────────────────────────────────────────────

class AuthService {
  AuthService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: true,
    ),
  );

  static GoogleSignIn _buildGoogleSignIn() {
    final clientId = DriverApiConfig.googleServerClientId.isNotEmpty
        ? DriverApiConfig.googleServerClientId
        : null;
    return GoogleSignIn(
      clientId: kIsWeb ? clientId : null,
      serverClientId: kIsWeb ? null : clientId,
      scopes: ['email', 'profile', 'openid'],
    );
  }

  // ── Google sign-in ──────────────────────────────────────────────────────────

  /// Triggers the Google sign-in flow and exchanges the ID token for our JWT.
  static Future<DriverModel?> signInWithGoogle() async {
    if (kIsWeb && DriverApiConfig.googleServerClientId.isEmpty) {
      throw const NetworkException(
        'Google Client ID is not set. Launch with --dart-define=GOOGLE_SERVER_CLIENT_ID=... or use Quick Dev Login below.',
      );
    }

    final googleSignIn = _buildGoogleSignIn();

    GoogleSignInAccount? account;
    try {
      account = await googleSignIn.signIn();
    } catch (e) {
      debugPrint('[AuthService] Google signIn error: $e');
      throw NetworkException('Google sign-in failed: $e');
    }

    if (account == null) {
      // User dismissed the picker
      return null;
    }

    // Get the ID token
    GoogleSignInAuthentication auth;
    try {
      auth = await account.authentication;
    } catch (e) {
      debugPrint('[AuthService] Google auth error: $e');
      throw NetworkException('Failed to get Google authentication: $e');
    }

    final token = auth.idToken ?? auth.accessToken;
    if (token == null) {
      throw const NetworkException(
        'Google did not return an authentication token. '
        'Ensure GOOGLE_SERVER_CLIENT_ID is set correctly.',
      );
    }

    // Exchange token for our own JWT
    final driver = await _postGoogleToken(token);
    return driver;
  }

  // ── Backend calls ───────────────────────────────────────────────────────────

  /// POST /auth/google — verify ID token, get our JWT, store it.
  static Future<DriverModel> _postGoogleToken(String idToken) async {
    final uri = Uri.parse('${DriverApiConfig.baseUrl}/auth/google');
    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'id_token': idToken}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw NetworkException('Cannot reach server: $e');
    }

    if (response.statusCode == 403) {
      throw const NotRegisteredDriverException();
    }
    if (response.statusCode == 401) {
      throw const NetworkException('Google token was rejected by the server.');
    }
    if (response.statusCode != 200) {
      throw ServerException(response.statusCode,
          _parseErrorDetail(response) ?? 'Unexpected error');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final jwt = body['access_token'] as String;
    final driverJson = body['driver'] as Map<String, dynamic>;
    final driver = DriverModel.fromJson(driverJson);

    // Persist token and profile
    await _storage.write(key: _kJwtKey, value: jwt);
    await _saveDriverProfile(driver);

    return driver;
  }

  /// POST /auth/dev-login — development only, bypasses Google.
  static Future<DriverModel> devSignIn(String email) async {
    final uri = Uri.parse('${DriverApiConfig.baseUrl}/auth/dev-login');
    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw NetworkException('Cannot reach server: $e');
    }

    if (response.statusCode == 403) {
      throw const NotRegisteredDriverException();
    }
    if (response.statusCode == 404) {
      throw const NetworkException(
        'Dev login is disabled on server (ALLOW_DEV_LOGIN=false).',
      );
    }
    if (response.statusCode != 200) {
      throw ServerException(
        response.statusCode,
        _parseErrorDetail(response) ?? 'Unexpected error',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final jwt = body['access_token'] as String;
    final driverJson = body['driver'] as Map<String, dynamic>;
    final driver = DriverModel.fromJson(driverJson);

    // Persist token and profile
    await _storage.write(key: _kJwtKey, value: jwt);
    await _saveDriverProfile(driver);

    return driver;
  }

  /// GET /drivers/me/ambulances — returns ambulances linked to the signed-in driver.
  static Future<List<AmbulanceModel>> fetchMyAmbulances() async {
    final jwt = await _storage.read(key: _kJwtKey);
    if (jwt == null) throw const NetworkException('Not authenticated.');

    final uri = Uri.parse('${DriverApiConfig.baseUrl}/drivers/me/ambulances');
    http.Response response;
    try {
      response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwt',
        },
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw NetworkException('Cannot reach server: $e');
    }

    if (response.statusCode == 401) {
      // Token expired — clear storage so the app drops back to Stage A
      await clearSession();
      throw const NetworkException('Session expired. Please sign in again.');
    }
    if (response.statusCode != 200) {
      throw ServerException(response.statusCode,
          _parseErrorDetail(response) ?? 'Unexpected error');
    }

    final list = jsonDecode(response.body) as List<dynamic>;
    return list
        .map((e) => AmbulanceModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Session persistence ─────────────────────────────────────────────────────

  /// Returns stored JWT, or null if none.
  static Future<String?> getStoredToken() => _storage.read(key: _kJwtKey);

  /// Returns stored [DriverModel], or null if none.
  static Future<DriverModel?> getStoredDriver() async {
    final idStr = await _storage.read(key: _kDriverIdKey);
    final name = await _storage.read(key: _kDriverNameKey);
    final email = await _storage.read(key: _kDriverEmailKey);
    if (idStr == null || name == null || email == null) return null;
    return DriverModel(
      id: int.parse(idStr),
      name: name,
      email: email,
      photoUrl: await _storage.read(key: _kDriverPhotoKey),
    );
  }

  /// Returns the saved selected ambulance, or null if none was chosen.
  static Future<({int id, String registrationNumber})?> getSelectedAmbulance() async {
    final idStr = await _storage.read(key: _kAmbulanceIdKey);
    final reg = await _storage.read(key: _kAmbulanceRegKey);
    if (idStr == null || reg == null) return null;
    return (id: int.parse(idStr), registrationNumber: reg);
  }

  /// Persist the chosen ambulance locally.
  static Future<void> saveSelectedAmbulance(AmbulanceModel ambulance) async {
    await _storage.write(key: _kAmbulanceIdKey, value: ambulance.id.toString());
    await _storage.write(key: _kAmbulanceRegKey, value: ambulance.registrationNumber);
  }

  /// Clear everything — token, driver profile, selected ambulance.
  static Future<void> clearSession() async {
    await _storage.deleteAll();
    try {
      await _buildGoogleSignIn().signOut();
    } catch (_) {}
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static Future<void> _saveDriverProfile(DriverModel driver) async {
    await _storage.write(key: _kDriverIdKey, value: driver.id.toString());
    await _storage.write(key: _kDriverNameKey, value: driver.name);
    await _storage.write(key: _kDriverEmailKey, value: driver.email);
    if (driver.photoUrl != null) {
      await _storage.write(key: _kDriverPhotoKey, value: driver.photoUrl!);
    }
  }

  static String? _parseErrorDetail(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['detail'] as String?;
    } catch (_) {
      return null;
    }
  }
}
