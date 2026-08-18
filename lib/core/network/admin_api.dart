import '../config/org_config.dart';
import 'api_client.dart';

class AdminOrg {
  const AdminOrg({
    required this.id,
    required this.name,
    required this.slug,
    this.meetingMode = MeetingMode.both,
    this.showTags = true,
  });
  final String id, name, slug;
  final MeetingMode meetingMode;
  final bool showTags;

  factory AdminOrg.fromJson(Map<String, dynamic> json) => AdminOrg(
    id: json['id'] as String,
    name: json['name'] as String,
    slug: (json['slug'] as String?) ?? '',
    meetingMode: MeetingMode.fromApi(json['meetingMode'] as String?),
    showTags: json['showTags'] as bool? ?? true,
  );
}

class AdminPermission {
  const AdminPermission({
    required this.id,
    required this.code,
    this.description = '',
  });
  final String id, code, description;

  factory AdminPermission.fromJson(Map<String, dynamic> json) =>
      AdminPermission(
        id: json['id'] as String,
        code: json['code'] as String,
        description: (json['description'] as String?) ?? '',
      );

  String get label {
    if (description.isNotEmpty) return description;
    return switch (code) {
      'task.create' => 'Create tasks',
      'task.assign' => 'Assign tasks',
      'task.update' => 'Update tasks',
      'task.view_all' => 'View all tasks',
      'expense.create' => 'Create expenses',
      'expense.approve' => 'Approve expenses',
      'expense.reject' => 'Reject expenses',
      'expense.reimburse' => 'Reimburse expenses',
      'expense.view_all' => 'View all expenses',
      'meeting.create' => 'Create meetings',
      'meeting.view_all' => 'View all meetings',
      'user.invite' => 'Create users',
      'user.update' => 'Update users',
      'role.manage' => 'Manage roles & permissions',
      'org.settings' => 'Organization settings',
      'activity.view' => 'View activity',
      _ => code,
    };
  }
}

class AdminRole {
  const AdminRole({
    required this.id,
    required this.name,
    required this.slug,
    this.isAdmin = false,
    this.isDefault = false,
    this.permissions = const [],
  });

  final String id, name, slug;
  final bool isAdmin, isDefault;
  final List<String> permissions;

  factory AdminRole.fromJson(Map<String, dynamic> json) => AdminRole(
    id: json['id'] as String,
    name: json['name'] as String,
    slug: json['slug'] as String,
    isAdmin: json['isAdmin'] as bool? ?? false,
    isDefault: json['isDefault'] as bool? ?? false,
    permissions: [
      for (final p in json['permissions'] as List? ?? []) p as String,
    ],
  );
}

class AdminApi {
  AdminApi(this._client);
  final ApiClient _client;

  Future<AdminOrg> getOrg() async {
    final res = await _client.dio.get<Map<String, dynamic>>('/admin/org');
    return AdminOrg.fromJson(res.data!);
  }

  Future<AdminOrg> updateOrg({
    String? name,
    MeetingMode? meetingMode,
    bool? showTags,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (meetingMode != null) data['meetingMode'] = meetingMode.apiValue;
    if (showTags != null) data['showTags'] = showTags;
    final res = await _client.dio.patch<Map<String, dynamic>>(
      '/admin/org',
      data: data,
    );
    return AdminOrg.fromJson(res.data!);
  }

  Future<AdminOrg> renameOrg(String name) => updateOrg(name: name);

  Future<List<AdminRole>> listRoles() async {
    final res = await _client.dio.get<List<dynamic>>('/admin/roles');
    return [
      for (final row in res.data ?? [])
        AdminRole.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<List<AdminPermission>> listPermissions() async {
    final res = await _client.dio.get<List<dynamic>>('/admin/permissions');
    return [
      for (final row in res.data ?? [])
        AdminPermission.fromJson(row as Map<String, dynamic>),
    ];
  }

  Future<AdminRole> updateRolePermissions({
    required String roleId,
    required List<String> permissions,
  }) async {
    final res = await _client.dio.patch<Map<String, dynamic>>(
      '/admin/roles/$roleId',
      data: {'permissions': permissions},
    );
    return AdminRole.fromJson(res.data!);
  }

  Future<List<Map<String, dynamic>>> listTaskStatuses() async {
    final res = await _client.dio.get<List<dynamic>>('/admin/task-statuses');
    return [
      for (final row in res.data ?? const [])
        Map<String, dynamic>.from(row as Map),
    ];
  }

  Future<Map<String, dynamic>> createTaskStatus({
    required String name,
    String color = '#6B7280',
    String icon = 'circle_outlined',
    bool isDefault = false,
    bool isDone = false,
  }) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/admin/task-statuses',
      data: {
        'name': name,
        'color': color,
        'icon': icon,
        'isDefault': isDefault,
        'isDone': isDone,
      },
    );
    return res.data!;
  }

  Future<Map<String, dynamic>> updateTaskStatus(
    String id, {
    String? name,
    String? color,
    String? icon,
    bool? isDefault,
    bool? isDone,
  }) async {
    final res = await _client.dio.patch<Map<String, dynamic>>(
      '/admin/task-statuses/$id',
      data: {
        if (name != null) 'name': name,
        if (color != null) 'color': color,
        if (icon != null) 'icon': icon,
        if (isDefault != null) 'isDefault': isDefault,
        if (isDone != null) 'isDone': isDone,
      },
    );
    return res.data!;
  }

  Future<void> deleteTaskStatus(String id) async {
    await _client.dio.delete('/admin/task-statuses/$id');
  }

  Future<List<Map<String, dynamic>>> listTaskPriorities() async {
    final res = await _client.dio.get<List<dynamic>>('/admin/task-priorities');
    return [
      for (final row in res.data ?? const [])
        Map<String, dynamic>.from(row as Map),
    ];
  }

  Future<Map<String, dynamic>> createTaskPriority({
    required String name,
    String color = '#6B7280',
    String icon = 'remove',
    bool isDefault = false,
  }) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/admin/task-priorities',
      data: {
        'name': name,
        'color': color,
        'icon': icon,
        'isDefault': isDefault,
      },
    );
    return res.data!;
  }

  Future<Map<String, dynamic>> updateTaskPriority(
    String id, {
    String? name,
    String? color,
    String? icon,
    bool? isDefault,
  }) async {
    final res = await _client.dio.patch<Map<String, dynamic>>(
      '/admin/task-priorities/$id',
      data: {
        if (name != null) 'name': name,
        if (color != null) 'color': color,
        if (icon != null) 'icon': icon,
        if (isDefault != null) 'isDefault': isDefault,
      },
    );
    return res.data!;
  }

  Future<void> deleteTaskPriority(String id) async {
    await _client.dio.delete('/admin/task-priorities/$id');
  }

  Future<List<Map<String, dynamic>>> listTaskTags() async {
    final res = await _client.dio.get<List<dynamic>>('/admin/task-tags');
    return [
      for (final row in res.data ?? const [])
        Map<String, dynamic>.from(row as Map),
    ];
  }

  Future<Map<String, dynamic>> createTaskTag({
    required String name,
    String color = '#6B7280',
    bool isDefault = false,
  }) async {
    final res = await _client.dio.post<Map<String, dynamic>>(
      '/admin/task-tags',
      data: {
        'name': name,
        'color': color,
        'isDefault': isDefault,
      },
    );
    return res.data!;
  }

  Future<Map<String, dynamic>> updateTaskTag(
    String id, {
    String? name,
    String? color,
    bool? isDefault,
  }) async {
    final res = await _client.dio.patch<Map<String, dynamic>>(
      '/admin/task-tags/$id',
      data: {
        if (name != null) 'name': name,
        if (color != null) 'color': color,
        if (isDefault != null) 'isDefault': isDefault,
      },
    );
    return res.data!;
  }

  Future<void> deleteTaskTag(String id) async {
    await _client.dio.delete('/admin/task-tags/$id');
  }
}
