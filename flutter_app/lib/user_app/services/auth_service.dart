import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'package:ambulance_app/user_app/config/api_config.dart';
import 'package:ambulance_app/user_app/models/user.dart';
import 'package:ambulance_app/user_app/services/api_service.dart' show ApiException;
import 'package:ambulance_app/user_app/services/user_storage.dart';

/// A Google account that has no user profile yet. The app must collect the
/// person's name and phone and call [UserAuthService.registerUser].
class PendingUserRegistration {
  const PendingUserRegistration({
    required this.registrationToken,
    required this.name,
    required this.email,
    this.photoUrl,
  });

  final String registrationToken;
  final String name;
  final String email;
  final String? photoUrl;
}

/// Result of a sign-in attempt: either a signed-in [user], or a
/// [registration] that still has to be completed.
class UserSignInOutcome {
  const UserSignInOutcome.signedIn(this.user) : registration = null;
  const UserSignInOutcome.needsRegistration(this.registration) : user = null;

  final User? user;
  final PendingUserRegistration? registration;
}

/// Google sign-in for the user app.
///
/// Exchanges a Google ID token for our own JWT (kept in secure storage) and
/// stores the signed-in [User] profile through [UserStorage].
class UserAuthService {
  UserAuthService({
    http.Client? client,
    FlutterSecureStorage? secureStorage,
    UserStorage? userStorage,
  })  : _client = client ?? http.Client(),
        _secure = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true),
            ),
        _userStorage = userStorage ?? UserStorage();

  static const _kJwtKey = 'user_jwt';
  static const Duration _timeout = Duration(seconds: 15);

  final http.Client _client;
  final FlutterSecureStorage _secure;
  final UserStorage _userStorage;

  GoogleSignIn _buildGoogleSignIn() {
    final clientId = ApiConfig.googleServerClientId.isNotEmpty
        ? ApiConfig.googleServerClientId
        : null;
    return GoogleSignIn(
      clientId: kIsWeb ? clientId : null,
      serverClientId: kIsWeb ? null : clientId,
      scopes: ['email', 'profile', 'openid'],
    );
  }

  /// The stored access token, or null when signed out.
  Future<String?> getToken() async {
    try {
      return await _secure.read(key: _kJwtKey);
    } catch (_) {
      return null;
    }
  }

  /// Runs the Google sign-in flow. Returns null if the person dismissed the
  /// account picker.
  Future<UserSignInOutcome?> signInWithGoogle() async {
    final googleSignIn = _buildGoogleSignIn();

    GoogleSignInAccount? account;
    try {
      account = await googleSignIn.signIn();
    } catch (e) {
      throw ApiException('Google sign-in failed: $e');
    }
    if (account == null) return null;

    final GoogleSignInAuthentication auth;
    try {
      auth = await account.authentication;
    } catch (e) {
      throw ApiException('Failed to get Google authentication: $e');
    }

    final token = auth.idToken ?? auth.accessToken;
    if (token == null) {
      throw const ApiException(
        'Google did not return an authentication token. '
        'Check that GOOGLE_SERVER_CLIENT_ID is set correctly.',
      );
    }

    final response = await _post(
      '/auth/google',
      {'id_token': token, 'role': 'user'},
    );
    return _handleAuthResponse(response);
  }

  /// Development only: signs in as [email] without Google. The server returns
  /// 404 unless ALLOW_DEV_LOGIN=true.
  Future<UserSignInOutcome> devSignIn(String email) async {
    final response = await _post(
      '/auth/dev-login',
      {'email': email, 'role': 'user'},
    );
    if (response.statusCode == 404) {
      throw const ApiException(
        'Dev login is disabled on the server (ALLOW_DEV_LOGIN=false).',
      );
    }
    return _handleAuthResponse(response);
  }

  /// Finishes registering a new user with the details collected after
  /// Google sign-in, and signs them in.
  Future<User> registerUser({
    required PendingUserRegistration registration,
    required String name,
    required String phone,
  }) async {
    final response = await _post('/auth/register/user', {
      'registration_token': registration.registrationToken,
      'name': name,
      'phone': phone,
    });
    final outcome = await _handleAuthResponse(response);
    return outcome.user!;
  }

  /// Forgets the session: token, saved profile and the Google account.
  Future<void> signOut() async {
    try {
      await _secure.delete(key: _kJwtKey);
    } catch (_) {}
    await _userStorage.clearUser();
    try {
      await _buildGoogleSignIn().signOut();
    } catch (_) {}
  }

  Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    try {
      return await _client
          .post(
            Uri.parse('${ApiConfig.baseUrl}$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(
        'The server took too long to respond. Please try again.',
      );
    } catch (_) {
      throw const ApiException(
        'Cannot reach the server. Check your connection and try again.',
      );
    }
  }

  Future<UserSignInOutcome> _handleAuthResponse(http.Response response) async {
    if (response.statusCode != 200 && response.statusCode != 201) {
      if (response.statusCode == 401) {
        throw ApiException(
            _detail(response) ?? 'Google sign-in was rejected by the server.');
      }
      throw ApiException(_detail(response) ??
          'Server returned status ${response.statusCode}. Please try again later.');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (body['registration_required'] == true) {
      final profile = body['google_profile'] as Map<String, dynamic>;
      return UserSignInOutcome.needsRegistration(PendingUserRegistration(
        registrationToken: body['registration_token'] as String,
        name: profile['name'] as String,
        email: profile['email'] as String,
        photoUrl: profile['photo_url'] as String?,
      ));
    }

    final user = User.fromJson(body['account'] as Map<String, dynamic>);
    await _secure.write(key: _kJwtKey, value: body['access_token'] as String);
    await _userStorage.saveUser(user);
    return UserSignInOutcome.signedIn(user);
  }

  String? _detail(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        final detail = body['detail'];
        if (detail is String) return detail;
        if (detail is List && detail.isNotEmpty && detail.first is Map) {
          return (detail.first as Map)['msg']?.toString();
        }
      }
    } catch (_) {}
    return null;
  }
}
