import 'package:flutter/foundation.dart';

/// API configuration for the Ambulance User App.
///
/// The [baseUrl] is injected at compile-time via --dart-define=API_BASE_URL=...
/// so no code changes are needed when switching environments.
///
/// Usage examples:
///   Development (LAN):   --dart-define=API_BASE_URL=http://192.168.1.10:8000
///   Android Emulator:    --dart-define=API_BASE_URL=http://10.0.2.2:8000
///                        (10.0.2.2 is the emulator's alias for the host machine)
///   Default (no define): http://localhost:8000 on Web/Desktop, http://10.0.2.2:8000 on Android
class ApiConfig {
  ApiConfig._(); // prevent instantiation

  /// The root URL of the FastAPI backend.
  /// Override at build time with --dart-define=API_BASE_URL=[your-server-url]
  static String get baseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }
    if (kIsWeb) {
      return 'http://localhost:8000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      // 127.0.0.1 forces IPv4 so ADB reverse forwards immediately over USB.
      // If running wirelessly on Wi-Fi, change to http://192.168.1.3:8000
      return 'http://127.0.0.1:8000';
    }
    return 'http://localhost:8000';
  }

  /// Demo fallback latitude (near seeded Kochi hospital cluster).
  /// Override with --dart-define=DEMO_LAT=...
  static double get demoLat {
    const val = String.fromEnvironment('DEMO_LAT', defaultValue: '9.9390');
    return double.tryParse(val) ?? 9.9390;
  }

  /// Demo fallback longitude (near seeded Kochi hospital cluster).
  /// Override with --dart-define=DEMO_LNG=...
  static double get demoLng {
    const val = String.fromEnvironment('DEMO_LNG', defaultValue: '76.2700');
    return double.tryParse(val) ?? 76.2700;
  }
}
