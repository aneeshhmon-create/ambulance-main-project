import 'package:flutter/foundation.dart';

/// API and auth configuration for the Ambulance Driver App.
///
/// Both values are injected at compile-time via --dart-define so no code
/// changes are needed when switching environments or Google projects.
///
/// Usage examples:
///   Development (LAN):
///     --dart-define=API_BASE_URL=http://192.168.1.10:8000
///     --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com
///   Android Emulator:
///     --dart-define=API_BASE_URL=http://10.0.2.2:8000
///                   (10.0.2.2 is the emulator's alias for the host machine)
class DriverApiConfig {
  DriverApiConfig._(); // prevent instantiation

  /// The root URL of the FastAPI backend.
  /// Override at build time with --dart-define=API_BASE_URL=[your-server-url]
  static String get baseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) return envUrl;
    if (kIsWeb) return 'http://localhost:8000';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://192.168.1.6:8000';
    }
    return 'http://localhost:8000';
  }

  /// The Web OAuth 2.0 client ID from Google Cloud Console.
  /// This is the same value as GOOGLE_CLIENT_ID on the backend.
  /// Passed to google_sign_in as `serverClientId` so we get an ID token.
  /// Override with --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com
  static const String googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
}
