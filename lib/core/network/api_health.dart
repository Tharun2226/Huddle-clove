import 'package:dio/dio.dart';

import 'api_config.dart';

/// Lightweight reachability check against Nest `GET /api/health`.
class ApiHealth {
  static Future<bool> isReachable({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: timeout,
          receiveTimeout: timeout,
          sendTimeout: timeout,
          validateStatus: (code) => code != null && code >= 200 && code < 300,
        ),
      );
      await dio.get<dynamic>(ApiConfig.healthUrl);
      return true;
    } catch (_) {
      return false;
    }
  }
}
