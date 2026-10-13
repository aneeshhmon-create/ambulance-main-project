/// API configuration for the Ambulance User App.
///
/// The [baseUrl] is injected at compile-time via --dart-define=API_BASE_URL=...
/// so no code changes are needed when switching environments.
///
/// Usage examples:
///   Development (LAN):   --dart-define=API_BASE_URL=http://192.168.1.10:8000
///   Android Emulator:    --dart-define=API_BASE_URL=http://10.0.2.2:8000
///                        (10.0.2.2 is the emulator's alias for the host machine)
///   Default (no define): http://192.168.1.10:8000
class ApiConfig {
  ApiConfig._(); // prevent instantiation

  /// The root URL of the FastAPI backend.
  /// Override at build time with --dart-define=API_BASE_URL=[your-server-url]
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.1.10:8000',
  );

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
