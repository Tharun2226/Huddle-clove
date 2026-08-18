import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_config.dart';

class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _accessKey = 'huddle_access_token';
  static const _refreshKey = 'huddle_refresh_token';

  final FlutterSecureStorage _storage;

  Future<String?> readAccess() => _storage.read(key: _accessKey);
  Future<String?> readRefresh() => _storage.read(key: _refreshKey);

  Future<void> save({required String access, required String refresh}) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}

class ApiClient {
  ApiClient(this._tokens) {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 45),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Memory cache avoids slow secure-storage reads on every tap.
          var token = _cachedAccess;
          if (token == null || token.isEmpty) {
            token = await _tokens.readAccess();
            _cachedAccess = token;
          }
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          // Let Dio set multipart boundary for FormData uploads.
          if (options.data is FormData) {
            options.headers.remove('Content-Type');
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401 && !_refreshing) {
            final refreshed = await _tryRefresh();
            if (refreshed) {
              final req = error.requestOptions;
              final token = _cachedAccess ?? await _tokens.readAccess();
              req.headers['Authorization'] = 'Bearer $token';
              try {
                final response = await _dio.fetch(req);
                return handler.resolve(response);
              } catch (_) {
                // fall through
              }
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  final TokenStore _tokens;
  late final Dio _dio;
  var _refreshing = false;
  String? _cachedAccess;

  Dio get dio => _dio;

  Future<bool> _tryRefresh() async {
    final refresh = await _tokens.readRefresh();
    if (refresh == null || refresh.isEmpty) return false;
    _refreshing = true;
    try {
      final res = await Dio(
        BaseOptions(
          baseUrl: ApiConfig.baseUrl,
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 20),
        ),
      ).post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refresh},
      );
      final data = res.data;
      if (data == null) return false;
      final access = data['accessToken'] as String;
      final nextRefresh = data['refreshToken'] as String;
      _cachedAccess = access;
      await _tokens.save(access: access, refresh: nextRefresh);
      return true;
    } catch (_) {
      _cachedAccess = null;
      await _tokens.clear();
      return false;
    } finally {
      _refreshing = false;
    }
  }

  /// Call after login / logout so the next request picks up the new token.
  void invalidateTokenCache() => _cachedAccess = null;

  /// Seed memory cache without rewriting secure storage (session restore).
  void seedAccessToken(String? access) {
    _cachedAccess = access;
  }

  Future<void> cacheTokens({
    required String access,
    required String refresh,
  }) async {
    _cachedAccess = access;
    await _tokens.save(access: access, refresh: refresh);
  }

  Future<void> clearTokens() async {
    _cachedAccess = null;
    await _tokens.clear();
  }
}
