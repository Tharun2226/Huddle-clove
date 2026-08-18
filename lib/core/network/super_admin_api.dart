import 'api_client.dart';

class SuperAdminOrg {
  const SuperAdminOrg({
    required this.id,
    required this.name,
    required this.slug,
    required this.createdAt,
    this.isActive = true,
    this.memberCount = 0,
  });

  final String id, name, slug;
  final DateTime createdAt;
  final bool isActive;
  final int memberCount;

  factory SuperAdminOrg.fromJson(Map<String, dynamic> json) => SuperAdminOrg(
    id: json['id'] as String,
    name: json['name'] as String,
    slug: (json['slug'] as String?) ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
    isActive: json['isActive'] as bool? ?? true,
    memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
  );
}

class OrgMember {
  const OrgMember({
    required this.id,
    required this.name,
    required this.email,
    this.title = '',
    required this.createdAt,
    this.roles = const [],
    this.isAdmin = false,
  });

  final String id, name, email, title;
  final DateTime createdAt;
  final List<String> roles;
  final bool isAdmin;

  factory OrgMember.fromJson(Map<String, dynamic> json) => OrgMember(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
    title: (json['title'] as String?) ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
    roles: [for (final r in (json['roles'] as List<dynamic>? ?? const [])) r as String],
    isAdmin: json['isAdmin'] as bool? ?? false,
  );
}

class OrgDetail {
  const OrgDetail({
    required this.id,
    required this.name,
    required this.slug,
    required this.createdAt,
    this.isActive = true,
    this.stats = const {},
    this.members = const [],
  });

  final String id, name, slug;
  final DateTime createdAt;
  final bool isActive;
  final Map<String, dynamic> stats;
  final List<OrgMember> members;

  factory OrgDetail.fromJson(Map<String, dynamic> json) => OrgDetail(
    id: json['id'] as String,
    name: json['name'] as String,
    slug: (json['slug'] as String?) ?? '',
    createdAt: DateTime.parse(json['createdAt'] as String),
    isActive: json['isActive'] as bool? ?? true,
    stats: (json['stats'] as Map<String, dynamic>?) ?? const {},
    members: [
      for (final m in (json['members'] as List<dynamic>? ?? const []))
        OrgMember.fromJson(m as Map<String, dynamic>),
    ],
  );
}

class SuperAdminApi {
  SuperAdminApi(this._client);
  final ApiClient _client;

  Future<List<SuperAdminOrg>> listOrganizations() async {
    final res = await _client.dio.get<List<dynamic>>('/super-admin/organizations');
    return [
      for (final row in res.data ?? const [])
        SuperAdminOrg.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<Map<String, dynamic>> createOrganization({
    required String organizationName,
    required String adminName,
    required String adminEmail,
    required String adminPassword,
    String? adminTitle,
  }) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/super-admin/organizations',
      data: {
        'organizationName': organizationName,
        'adminName': adminName,
        'adminEmail': adminEmail,
        'adminPassword': adminPassword,
        if (adminTitle != null && adminTitle.isNotEmpty) 'adminTitle': adminTitle,
      },
    );
    return res.data!;
  }

  Future<OrgDetail> getOrganizationDetail(String orgId) async {
    final res = await _client.dio.get<Map<String, dynamic>>(
      '/super-admin/organizations/$orgId',
    );
    return OrgDetail.fromJson(res.data!);
  }

  Future<void> setOrganizationActive(String orgId, bool isActive) async {
    await _client.dio.patch<void>(
      '/super-admin/organizations/$orgId/status',
      data: {'isActive': isActive},
    );
  }
}
