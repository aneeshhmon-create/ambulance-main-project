// lib/driver_app/services/auth_service.dart
//
// Handles Google sign-in, first-time driver registration, backend JWT
// exchange, secure token storage, and fetching the driver's linked ambulances.
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
const _kDriverPhoneKey = 'driver_phone';
const _kDriverPhotoKey = 'driver_photo_url';
const _kAmbulanceIdKey = 'selected_ambulance_id';
const _kAmbulanceRegKey = 'selected_ambulance_reg';
const _kAmbulanceTypeKey = 'selected_ambulance_type';
const _kAmbulanceOnlineKey = 'selected_ambulance_online';
const _kActiveIncidentIdKey = 'driver_active_incident_id';

// ── Exceptions ────────────────────────────────────────────────────────────────

/// The server refused the account (e.g. a deactivated driver).
class AccountDisabledException implements Exception {
  final String message;
  const AccountDisabledException(
      [this.message = 'This driver account has been deactivated.']);
  @override
  String toString() => message;
}

/// A Google account that has no driver profile yet. The app must collect the
/// driver's name and phone and call [AuthService.registerDriver].
class PendingDriverRegistration {
  final String registrationToken;
  final String name;
  final String email;
  final String? photoUrl;

  const PendingDriverRegistration({
    required this.registrationToken,
    required this.name,
    required this.email,
    this.photoUrl,
  });
}

/// Result of a sign-in attempt: either a signed-in [driver], or a
/// [registration] that still has to be completed.
class DriverSignInOutcome {
  final DriverModel? driver;
  final PendingDriverRegistration? registration;

  const DriverSignInOutcome.signedIn(this.driver) : registration = null;
  const DriverSignInOutcome.needsRegistration(this.registration)
      : driver = null;
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
  /// Returns null if the person dismissed the Google account picker.
  static Future<DriverSignInOutcome?> signInWithGoogle() async {
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
    return _postGoogleToken(token);
  }

  // ── Backend calls ───────────────────────────────────────────────────────────

  /// POST /auth/google — verify ID token, get our JWT (or a registration
  /// token for a first-time driver).
  static Future<DriverSignInOutcome> _postGoogleToken(String idToken) async {
    final response = await _post(
      '/auth/google',
      {'id_token': idToken, 'role': 'driver'},
    );
    return _handleAuthResponse(response);
  }

  /// POST /auth/dev-login — development only, bypasses Google.
  static Future<DriverSignInOutcome> devSignIn(String email) async {
    final response = await _post(
      '/auth/dev-login',
      {'email': email, 'role': 'driver'},
    );
    if (response.statusCode == 404) {
      throw const NetworkException(
        'Dev login is disabled on server (ALLOW_DEV_LOGIN=false).',
      );
    }
    return _handleAuthResponse(response);
  }

  /// POST /auth/register/driver — finish registering a new driver.
  static Future<DriverModel> registerDriver({
    required PendingDriverRegistration registration,
    required String name,
    required String phone,
  }) async {
    final response = await _post('/auth/register/driver', {
      'registration_token': registration.registrationToken,
      'name': name,
      'phone': phone,
    });
    if (response.statusCode == 401) {
      throw NetworkException(_parseErrorDetail(response) ??
          'Registration expired. Please sign in with Google again.');
    }
    if (response.statusCode == 409 || response.statusCode == 422) {
      throw ServerException(response.statusCode,
          _parseErrorDetail(response) ?? 'Could not register this driver.');
    }
    final outcome = await _handleAuthResponse(response);
    return outcome.driver!;
  }

  static Future<http.Response> _post(
      String path, Map<String, dynamic> body) async {
    try {
      return await http
          .post(
            Uri.parse('${DriverApiConfig.baseUrl}$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw NetworkException('Cannot reach server: $e');
    }
  }

  /// Interprets a /auth/* response: persists the session when signed in,
  /// or returns the pending registration for a new driver.
  static Future<DriverSignInOutcome> _handleAuthResponse(
      http.Response response) async {
    if (response.statusCode == 403) {
      throw AccountDisabledException(
          _parseErrorDetail(response) ?? 'This account is not allowed to sign in.');
    }
    if (response.statusCode == 401) {
      throw const NetworkException('Google token was rejected by the server.');
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ServerException(response.statusCode,
          _parseErrorDetail(response) ?? 'Unexpected error');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (body['registration_required'] == true) {
      final profile = body['google_profile'] as Map<String, dynamic>;
      return DriverSignInOutcome.needsRegistration(PendingDriverRegistration(
        registrationToken: body['registration_token'] as String,
        name: profile['name'] as String,
        email: profile['email'] as String,
        photoUrl: profile['photo_url'] as String?,
      ));
    }

    final jwt = body['access_token'] as String;
    final driver =
        DriverModel.fromJson(body['account'] as Map<String, dynamic>);

    // Persist token and profile
    await _storage.write(key: _kJwtKey, value: jwt);
    await _saveDriverProfile(driver);

    return DriverSignInOutcome.signedIn(driver);
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
      phone: await _storage.read(key: _kDriverPhoneKey),
      photoUrl: await _storage.read(key: _kDriverPhotoKey),
    );
  }

  /// Returns the saved selected ambulance, or null if none was chosen.
  static Future<AmbulanceModel?> getSelectedAmbulance() async {
    final idStr = await _storage.read(key: _kAmbulanceIdKey);
    final reg = await _storage.read(key: _kAmbulanceRegKey);
    if (idStr == null || reg == null) return null;
    final onlineStr = await _storage.read(key: _kAmbulanceOnlineKey);
    return AmbulanceModel(
      id: int.parse(idStr),
      registrationNumber: reg,
      vehicleType: await _storage.read(key: _kAmbulanceTypeKey),
      isAvailable: true,
      isOnline: onlineStr == 'true',
    );
  }

  /// Persist the chosen ambulance locally.
  static Future<void> saveSelectedAmbulance(AmbulanceModel ambulance) async {
    await _storage.write(key: _kAmbulanceIdKey, value: ambulance.id.toString());
    await _storage.write(key: _kAmbulanceRegKey, value: ambulance.registrationNumber);
    if (ambulance.vehicleType != null) {
      await _storage.write(key: _kAmbulanceTypeKey, value: ambulance.vehicleType!);
    }
    await _storage.write(key: _kAmbulanceOnlineKey, value: ambulance.isOnline.toString());
  }

  /// Update only the persisted isOnline flag (called by home screen after toggle).
  static Future<void> updateStoredOnlineState(bool isOnline) async {
    await _storage.write(key: _kAmbulanceOnlineKey, value: isOnline.toString());
  }

  /// Persist the active incident ID during driving navigation.
  static Future<void> saveActiveIncidentId(int incidentId) async {
    await _storage.write(key: _kActiveIncidentIdKey, value: incidentId.toString());
  }

  /// Get the active incident ID, or null if none.
  static Future<int?> getActiveIncidentId() async {
    final idStr = await _storage.read(key: _kActiveIncidentIdKey);
    return idStr != null ? int.tryParse(idStr) : null;
  }

  /// Clear the active incident ID (e.g. mission completed or cancelled).
  static Future<void> clearActiveIncidentId() async {
    await _storage.delete(key: _kActiveIncidentIdKey);
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
    if (driver.phone != null) {
      await _storage.write(key: _kDriverPhoneKey, value: driver.phone!);
    }
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
