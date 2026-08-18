/// Nest API wiring.
///
/// Override with:
/// `flutter run --dart-define=API_BASE_URL=https://api.example.com/api`
class ApiConfig {
  /// Nest API root (includes `/api`).
  /// Production default: Vercel. Override locally with `--dart-define=API_BASE_URL=...`
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://huddle-backend-api.vercel.app/api',
  );

  /// Origin used for static files like `/uploads/...` (API lives under `/api`).
  static String get origin {
    final url = baseUrl;
    if (url.endsWith('/api')) {
      return url.substring(0, url.length - 4);
    }
    if (url.endsWith('/api/')) {
      return url.substring(0, url.length - 5);
    }
    return url;
  }

  /// `GET {baseUrl}/health`
  static String get healthUrl {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$base/health';
  }

  /// Turn a relative receipt path into a full URL the Image widget can load.
  static String resolveMediaUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    if (path.startsWith('/')) return '$origin$path';
    return '$origin/$path';
  }
}
