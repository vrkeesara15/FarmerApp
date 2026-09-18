/// Where the API lives. Override at build time:
/// `flutter run --dart-define=API_BASE_URL=https://api.dev.farmerapp.in`.
///
/// The default targets the host machine from the Android emulator
/// (`10.0.2.2` = host loopback) where `make up` + `uvicorn` serve port 8000.
class ApiConfig {
  /// Creates a config.
  const ApiConfig({this.baseUrl = defaultBaseUrl});

  /// Compile-time base URL (no trailing slash).
  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Base URL without a trailing slash.
  final String baseUrl;

  /// Resolves an API path (e.g. `/v1/me`).
  Uri resolve(String path) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$base$path');
  }
}
