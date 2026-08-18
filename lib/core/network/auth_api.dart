import '../auth/domain/app_user.dart';
import '../config/org_config.dart';
import 'api_client.dart';

class AuthResult {
  const AuthResult(this.user, this.config);
  final AppUser user;
  final OrgConfig? config;
}

class AuthApi {
  AuthApi(this._client, this._tokens);

  final ApiClient _client;
  final TokenStore _tokens;

  Future<AuthResult?> tryRestoreSession() async {
    final refresh = await _tokens.readRefresh();
    final access = await _tokens.readAccess();
    if ((refresh == null || refresh.isEmpty) &&
        (access == null || access.isEmpty)) {
      return null;
    }
    if (access != null && access.isNotEmpty) {
      _client.seedAccessToken(access);
    }
    try {
      return await me();
    } catch (_) {
      await _client.clearTokens();
      return null;
    }
  }

  Future<AuthResult> login({required String email, required String password}) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': email, 'password': password},
    );
    final data = res.data!;
    await _client.cacheTokens(
      access: data['accessToken'] as String,
      refresh: data['refreshToken'] as String,
    );
    return AuthResult(
      _mapUser(data['user'] as Map<String, dynamic>),
      _mapConfig(data['config'] as Map<String, dynamic>?),
    );
  }

  Future<AuthResult> me() async {
    final res = await _client.dio.get<Map<String, dynamic>>('/auth/me');
    final data = res.data!;
    final userJson = data.containsKey('user') ? data['user'] as Map<String, dynamic> : data;
    return AuthResult(
      _mapUser(userJson),
      _mapConfig(data['config'] as Map<String, dynamic>?),
    );
  }

  Future<List<AppUser>> listUsers() async {
    final res = await _client.dio.get<List<dynamic>>('/users');
    return [
      for (final row in res.data ?? const [])
        _mapUser(row as Map<String, dynamic>),
    ];
  }

  Future<AppUser> createUser({
    required String email,
    required String name,
    required String password,
    String? roleId,
    String? managerId,
    UserRole? role,
    String? title,
  }) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/users/invite',
      data: {
        'email': email,
        'name': name,
        'password': password,
        if (roleId != null && roleId.isNotEmpty) 'roleId': roleId,
        if (title != null && title.isNotEmpty) 'title': title,
        if (managerId != null) 'managerId': managerId,
      },
    );
    return _mapUser(res.data!);
  }

  Future<AppUser> updateUser({
    required String id,
    String? roleId,
    String? managerId,
    UserRole? role,
    String? title,
    String? name,
  }) async {
    final res = await _client.dio.patch<Map<String, dynamic>>(
      '/users/$id',
      data: {
        if (roleId != null && roleId.isNotEmpty) 'roleId': roleId,
        if (title != null) 'title': title,
        if (name != null) 'name': name,
        if (managerId != null) 'managerId': managerId,
      },
    );
    return _mapUser(res.data!);
  }

  Future<void> logout() async {
    final refresh = await _tokens.readRefresh();
    if (refresh != null) {
      try {
        await _client.dio.post('/auth/logout', data: {'refreshToken': refresh});
      } catch (_) {}
    }
    await _client.clearTokens();
  }

  AppUser _mapUser(Map<String, dynamic> json) {
    final roleStr = (json['role'] as String?) ?? '';
    final role = switch (roleStr.toLowerCase()) {
      'admin' => UserRole.admin,
      'manager' => UserRole.manager,
      _ => UserRole.member,
    };
    final isAdmin = json['isAdmin'] as bool? ?? false;
    final isSuperAdmin = json['isSuperAdmin'] as bool? ?? false;
    final roleNames = <String>[
      for (final r in (json['roles'] as List<dynamic>? ?? const [])) r as String,
    ];
    return AppUser(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      role: role,
      title: (json['title'] as String?) ?? '',
      isAdmin: isAdmin,
      isSuperAdmin: isSuperAdmin,
      roleNames: roleNames,
      managerId: json['managerId'] as String?,
      managerName: json['managerName'] as String?,
    );
  }

  OrgConfig? _mapConfig(Map<String, dynamic>? json) {
    if (json == null) return null;
    return OrgConfig.fromJson(json);
  }
}
