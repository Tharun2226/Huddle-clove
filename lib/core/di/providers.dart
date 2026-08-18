import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/expenses/data/expense_repository.dart';
import '../../features/team/data/activity_repository.dart';
import '../../features/team/domain/activity_event.dart';
import '../../features/tasks_meetings/data/task_repository.dart';
import '../config/org_config.dart';
import '../network/api_activity_repository.dart';
import '../network/api_client.dart';
import '../network/api_expense_repository.dart';
import '../network/api_task_repository.dart';
import '../network/admin_api.dart';
import '../network/auth_api.dart';
import '../network/super_admin_api.dart';
import '../network/http_activity_repository.dart';
import '../network/http_expense_repository.dart';
import '../network/http_task_repository.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(tokenStoreProvider)),
);

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(apiClientProvider), ref.watch(tokenStoreProvider)),
);

final superAdminApiProvider = Provider<SuperAdminApi>(
  (ref) => SuperAdminApi(ref.watch(apiClientProvider)),
);

final adminApiProvider = Provider<AdminApi>(
  (ref) => AdminApi(ref.watch(apiClientProvider)),
);

final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  final repo = HttpActivityRepository(
    ApiActivityRepository(ref.watch(apiClientProvider)),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final activityRecorderProvider = Provider<ActivityRecorder>((ref) {
  final repo = ref.watch(activityRepositoryProvider);
  if (repo is ActivityRecorder) return repo as ActivityRecorder;
  return _NoopActivityRecorder();
});

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  final repo = HttpTaskRepository(
    ApiTaskRepository(ref.watch(apiClientProvider)),
    () => ref.read(orgConfigProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  final repo = HttpExpenseRepository(
    ApiExpenseRepository(ref.watch(apiClientProvider)),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

class _NoopActivityRecorder implements ActivityRecorder {
  @override
  void record({
    required String actorId,
    required ActivityType type,
    required String subject,
    double? amount,
    String? targetId,
  }) {}
}

/// Follows the system by default; the toggle in Settings overrides it.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void set(ThemeMode mode) => state = mode;
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
