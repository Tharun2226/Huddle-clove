import 'package:flutter/foundation.dart';

/// Mirrors the Firebase Auth custom claim `role: manager | member` described in
/// the build guide. Role checks must be re-enforced in the BFF once it exists —
/// hiding UI is convenience, not security.
enum UserRole {
  admin('Admin'),
  manager('Manager'),
  member('Team Member');

  const UserRole(this.label);
  final String label;

  bool get isManager => this == UserRole.manager || this == UserRole.admin;
}

@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.title = '',
    this.isAdmin = false,
    this.isSuperAdmin = false,
    this.roleNames = const [],
    this.managerId,
    this.managerName,
  });

  final String id;
  final String name;
  final String email;
  final UserRole role;
  final String title;
  final bool isAdmin;
  final bool isSuperAdmin;
  final List<String> roleNames;
  final String? managerId;
  final String? managerName;

  bool get isManager => isAdmin || role.isManager;

  /// Can approve/reject submitted expenses (admin or manager).
  bool get canApproveExpenses => isAdmin || role == UserRole.admin || role == UserRole.manager;

  /// First one or two name parts for greetings (e.g. "Sri Karthik").
  String get firstName {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first;
    return '${parts[0]} ${parts[1]}';
  }

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final only = parts.first;
      return (only.length >= 2 ? only.substring(0, 2) : only).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  AppUser copyWith({
    UserRole? role,
    bool? isAdmin,
    bool? isSuperAdmin,
    List<String>? roleNames,
    String? managerId,
    String? managerName,
  }) => AppUser(
    id: id,
    name: name,
    email: email,
    role: role ?? this.role,
    title: title,
    isAdmin: isAdmin ?? this.isAdmin,
    isSuperAdmin: isSuperAdmin ?? this.isSuperAdmin,
    roleNames: roleNames ?? this.roleNames,
    managerId: managerId ?? this.managerId,
    managerName: managerName ?? this.managerName,
  );

  @override
  bool operator ==(Object other) => other is AppUser && other.id == id && other.role == role && other.isSuperAdmin == isSuperAdmin;

  @override
  int get hashCode => Object.hash(id, role, isSuperAdmin);
}
