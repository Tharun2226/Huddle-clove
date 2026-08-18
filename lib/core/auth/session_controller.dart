import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/org_config.dart';
import '../di/providers.dart';
import 'domain/app_user.dart';

/// True once a stored JWT session has been checked (success or not).
final sessionBootstrapProvider = FutureProvider<void>((ref) async {
  await ref.read(sessionControllerProvider.notifier).restoreSession();
});

/// Auth session — NestJS JWT only.
class SessionController extends Notifier<AppUser?> {
  @override
  AppUser? build() => null;

  /// Rehydrate the signed-in user from secure storage on cold start.
  Future<void> restoreSession() async {
    if (state != null) return;
    final result = await ref.read(authApiProvider).tryRestoreSession();
    if (result == null) return;
    if (result.config != null) {
      ref.read(orgConfigProvider.notifier).set(result.config!);
    }
    state = result.user;
  }

  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final result = await ref.read(authApiProvider).login(
          email: email,
          password: password,
        );
    if (result.config != null) {
      ref.read(orgConfigProvider.notifier).set(result.config!);
    }
    state = result.user;
    // Fresh session → drop any stale in-memory snapshots from a prior login.
    ref.invalidate(taskRepositoryProvider);
    ref.invalidate(expenseRepositoryProvider);
    ref.invalidate(activityRepositoryProvider);
    ref.invalidate(remoteTeamProvider);
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
    return ref.read(authApiProvider).createUser(
          email: email,
          name: name,
          password: password,
          roleId: roleId,
          managerId: managerId,
          role: role,
          title: title,
        );
  }

  Future<AppUser> updateTeammate({
    required String id,
    String? roleId,
    String? managerId,
    UserRole? role,
    String? title,
    String? name,
  }) async {
    final updated = await ref.read(authApiProvider).updateUser(
          id: id,
          roleId: roleId,
          managerId: managerId,
          role: role,
          title: title,
          name: name,
        );
    final me = state;
    if (me != null && me.id == updated.id) {
      state = updated;
    }
    return updated;
  }

  Future<void> signOut() async {
    try {
      await ref.read(authApiProvider).logout();
    } catch (_) {}
    state = null;
    ref.invalidate(taskRepositoryProvider);
    ref.invalidate(expenseRepositoryProvider);
    ref.invalidate(activityRepositoryProvider);
    ref.invalidate(remoteTeamProvider);
    ref.read(orgConfigProvider.notifier).set(const OrgConfig());
  }
}

final sessionControllerProvider = NotifierProvider<SessionController, AppUser?>(
  SessionController.new,
);

final currentUserProvider = Provider<AppUser>((ref) {
  final user = ref.watch(sessionControllerProvider);
  if (user == null) {
    throw StateError('currentUserProvider read while signed out');
  }
  return user;
});

final isManagerProvider = Provider<bool>(
  (ref) => ref.watch(sessionControllerProvider)?.isManager ?? false,
);

final remoteTeamProvider = FutureProvider<List<AppUser>>((ref) async {
  final userId = ref.watch(sessionControllerProvider.select((u) => u?.id));
  if (userId == null) return const [];
  return ref.read(authApiProvider).listUsers();
});

/// Team directory from `/users`. Always includes the signed-in user.
final teamProvider = Provider<List<AppUser>>((ref) {
  final me = ref.watch(sessionControllerProvider);
  if (me == null) return const [];

  final asyncTeam = ref.watch(remoteTeamProvider);
  final loaded = asyncTeam.asData?.value ?? asyncTeam.value;
  if (loaded == null || loaded.isEmpty) return [me];

  final byId = {for (final user in loaded) user.id: user};
  byId[me.id] = me;
  return byId.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
});

final teamById = Provider<Map<String, AppUser>>(
  (ref) => {for (final user in ref.watch(teamProvider)) user.id: user},
);

extension UserLookup on Map<String, AppUser> {
  AppUser resolve(String id, {String? fallbackName}) =>
      this[id] ??
      AppUser(
        id: id,
        name: (fallbackName != null && fallbackName.trim().isNotEmpty)
            ? fallbackName.trim()
            : 'Unknown',
        email: '',
        role: UserRole.member,
      );
}
