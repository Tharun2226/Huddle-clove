import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class OrgRole {
  const OrgRole({
    required this.id,
    required this.name,
    required this.slug,
    this.isAdmin = false,
    this.isDefault = false,
  });
  final String id, name, slug;
  final bool isAdmin, isDefault;

  factory OrgRole.fromJson(Map<String, dynamic> json) => OrgRole(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        isAdmin: json['isAdmin'] as bool? ?? false,
        isDefault: json['isDefault'] as bool? ?? false,
      );
}

@immutable
class OrgTaskStatus {
  const OrgTaskStatus({
    required this.id,
    required this.name,
    required this.slug,
    this.color = '#6B7280',
    this.icon = 'circle_outlined',
    this.isDefault = false,
    this.isDone = false,
  });
  final String id, name, slug, color, icon;
  final bool isDefault, isDone;

  factory OrgTaskStatus.fromJson(Map<String, dynamic> json) => OrgTaskStatus(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        color: (json['color'] as String?) ?? '#6B7280',
        icon: (json['icon'] as String?) ?? 'circle_outlined',
        isDefault: json['isDefault'] as bool? ?? false,
        isDone: json['isDone'] as bool? ?? false,
      );
}

@immutable
class OrgTaskPriority {
  const OrgTaskPriority({
    required this.id,
    required this.name,
    required this.slug,
    this.color = '#6B7280',
    this.icon = 'remove',
    this.isDefault = false,
  });
  final String id, name, slug, color, icon;
  final bool isDefault;

  factory OrgTaskPriority.fromJson(Map<String, dynamic> json) =>
      OrgTaskPriority(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        color: (json['color'] as String?) ?? '#6B7280',
        icon: (json['icon'] as String?) ?? 'remove',
        isDefault: json['isDefault'] as bool? ?? false,
      );
}

@immutable
class OrgTaskTag {
  const OrgTaskTag({
    required this.id,
    required this.name,
    required this.slug,
    this.color = '#6B7280',
    this.isDefault = false,
  });
  final String id, name, slug, color;
  final bool isDefault;

  factory OrgTaskTag.fromJson(Map<String, dynamic> json) => OrgTaskTag(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        color: (json['color'] as String?) ?? '#6B7280',
        isDefault: json['isDefault'] as bool? ?? false,
      );
}

@immutable
class OrgConfig {
  const OrgConfig({
    this.meetingMode = MeetingMode.both,
    this.showTags = true,
    this.roles = const [],
    this.taskStatuses = const [],
    this.taskPriorities = const [],
    this.taskTags = const [],
  });

  final MeetingMode meetingMode;
  final bool showTags;
  final List<OrgRole> roles;
  final List<OrgTaskStatus> taskStatuses;
  final List<OrgTaskPriority> taskPriorities;
  final List<OrgTaskTag> taskTags;

  factory OrgConfig.fromJson(Map<String, dynamic> json) => OrgConfig(
        meetingMode: MeetingMode.fromApi(json['meetingMode'] as String?),
        showTags: json['showTags'] as bool? ?? true,
        roles: [
          for (final r in json['roles'] as List? ?? [])
            OrgRole.fromJson(r as Map<String, dynamic>),
        ],
        taskStatuses: [
          for (final s in json['taskStatuses'] as List? ?? [])
            OrgTaskStatus.fromJson(s as Map<String, dynamic>),
        ],
        taskPriorities: [
          for (final p in json['taskPriorities'] as List? ?? [])
            OrgTaskPriority.fromJson(p as Map<String, dynamic>),
        ],
        taskTags: [
          for (final t in json['taskTags'] as List? ?? [])
            OrgTaskTag.fromJson(t as Map<String, dynamic>),
        ],
      );

  OrgTaskStatus? get defaultStatus =>
      taskStatuses.where((s) => s.isDefault).firstOrNull;
  OrgTaskStatus? get doneStatus =>
      taskStatuses.where((s) => s.isDone).firstOrNull;
  OrgTaskPriority? get defaultPriority =>
      taskPriorities.where((p) => p.isDefault).firstOrNull;
  OrgTaskTag? get defaultTag => taskTags.where((t) => t.isDefault).firstOrNull;

  bool get allowsOnlineMeetings =>
      meetingMode == MeetingMode.both || meetingMode == MeetingMode.onlineOnly;
  bool get allowsInPersonMeetings =>
      meetingMode == MeetingMode.both ||
      meetingMode == MeetingMode.inPersonOnly;
}

enum MeetingMode {
  both('BOTH', 'Both'),
  onlineOnly('ONLINE_ONLY', 'Online only'),
  inPersonOnly('IN_PERSON_ONLY', 'In person only');

  const MeetingMode(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static MeetingMode fromApi(String? raw) => switch ((raw ?? '').toUpperCase()) {
        'ONLINE_ONLY' => MeetingMode.onlineOnly,
        'IN_PERSON_ONLY' => MeetingMode.inPersonOnly,
        _ => MeetingMode.both,
      };
}

class OrgConfigNotifier extends Notifier<OrgConfig> {
  @override
  OrgConfig build() => const OrgConfig();

  void set(OrgConfig config) => state = config;
}

final orgConfigProvider = NotifierProvider<OrgConfigNotifier, OrgConfig>(
  OrgConfigNotifier.new,
);
