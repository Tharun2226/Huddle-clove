import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/dashboard/presentation/today_screen.dart';
import '../../features/expenses/domain/expense.dart';
import '../../features/expenses/presentation/screens/add_expense_screen.dart';
import '../../features/expenses/presentation/screens/expense_detail_screen.dart';
import '../../features/expenses/presentation/screens/expenses_screen.dart';
import '../../features/admin/presentation/screens/org_settings_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/super_admin/presentation/screens/super_admin_dashboard.dart';
import '../../features/tasks_meetings/presentation/screens/task_detail_screen.dart';
import '../../features/tasks_meetings/presentation/screens/task_editor_screen.dart';
import '../../features/tasks_meetings/presentation/screens/tasks_screen.dart';
import '../../features/team/presentation/screens/team_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../auth/domain/app_user.dart';
import '../auth/session_controller.dart';
import '../../features/auth/presentation/login_screen.dart';
import 'home_shell.dart';

abstract final class Routes {
  static const login = '/login';
  static const superAdmin = '/super-admin';
  static const orgSettings = '/org-settings';
  static const today = '/today';
  static const tasks = '/tasks';
  static const expenses = '/expenses';
  static const team = '/team';
  static const settings = '/settings';
  static const notifications = '/notifications';

  static String taskDetail(String id) => '/tasks/$id';
  static const newTask = '/tasks/new';
  static String editTask(String id) => '/tasks/$id/edit';
  static String expenseDetail(String id) => '/expenses/$id';
  static const newExpense = '/expenses/new';

  /// Create-task route with an optional prefilled due calendar day (`YYYY-MM-DD`).
  static String newTaskWithDue(DateTime day) {
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return '$newTask?due=$y-$m-$d';
  }
}

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _todayKey = GlobalKey<NavigatorState>(debugLabel: 'today');
final _tasksKey = GlobalKey<NavigatorState>(debugLabel: 'tasks');
final _expensesKey = GlobalKey<NavigatorState>(debugLabel: 'expenses');
final _teamKey = GlobalKey<NavigatorState>(debugLabel: 'team');

/// Latest [GoRouter] instance — used by FCM taps without reading [routerProvider]
/// (avoids Riverpod circular deps during session updates).
GoRouter? appGoRouter;

final routerProvider = Provider<GoRouter>((ref) {
  // Bridges Riverpod's session state into go_router's Listenable-based refresh.
  final authState = ValueNotifier<AppUser?>(ref.read(sessionControllerProvider));
  ref.listen<AppUser?>(
    sessionControllerProvider,
    (_, next) => authState.value = next,
  );
  ref.onDispose(authState.dispose);

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.today,
    refreshListenable: authState,
    redirect: (context, state) {
      final user = ref.read(sessionControllerProvider);
      final atLogin = state.matchedLocation == Routes.login;

      if (user == null) return atLogin ? null : Routes.login;
      if (atLogin) return user.isSuperAdmin ? Routes.superAdmin : Routes.today;

      if (user.isSuperAdmin && !state.matchedLocation.startsWith(Routes.superAdmin)) {
        return Routes.superAdmin;
      }
      if (!user.isSuperAdmin && state.matchedLocation.startsWith(Routes.superAdmin)) {
        return Routes.today;
      }

      // The Team tab is manager-only. Hiding the nav item is not enough — a
      // deep link or a role switch while on the tab has to bounce too.
      if (!user.isManager && state.matchedLocation.startsWith(Routes.team)) {
        return Routes.today;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.superAdmin,
        builder: (context, state) => const SuperAdminDashboard(),
      ),
      GoRoute(
        path: Routes.settings,
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: Routes.orgSettings,
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const OrgSettingsScreen(),
      ),
      GoRoute(
        path: Routes.notifications,
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const NotificationsScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _todayKey,
            routes: [
              GoRoute(
                path: Routes.today,
                builder: (context, state) => const TodayScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _tasksKey,
            routes: [
              GoRoute(
                path: Routes.tasks,
                builder: (context, state) => const TasksScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: _rootKey,
                    builder: (context, state) {
                      final assignee = state.uri.queryParameters['assignee'];
                      final dueRaw = state.uri.queryParameters['due'];
                      DateTime? dueDay;
                      if (dueRaw != null && dueRaw.isNotEmpty) {
                        dueDay = DateTime.tryParse(dueRaw);
                        if (dueDay != null) {
                          dueDay = DateTime(
                            dueDay.year,
                            dueDay.month,
                            dueDay.day,
                          );
                        }
                      }
                      return TaskEditorScreen(
                        initialAssigneeId: assignee,
                        initialDueDate: dueDay,
                      );
                    },
                  ),
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootKey,
                    builder: (context, state) =>
                        TaskDetailScreen(taskId: state.pathParameters['id']!),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        parentNavigatorKey: _rootKey,
                        builder: (context, state) =>
                            TaskEditorScreen(taskId: state.pathParameters['id']),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _expensesKey,
            routes: [
              GoRoute(
                path: Routes.expenses,
                builder: (context, state) => const ExpensesScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    parentNavigatorKey: _rootKey,
                    builder: (context, state) => AddExpenseScreen(
                      editing: state.extra is Expense ? state.extra as Expense : null,
                    ),
                  ),
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: _rootKey,
                    builder: (context, state) =>
                        ExpenseDetailScreen(expenseId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _teamKey,
            routes: [
              GoRoute(
                path: Routes.team,
                builder: (context, state) => const TeamScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => _RouteErrorScreen(message: state.error?.toString()),
  );
  appGoRouter = router;
  ref.onDispose(() {
    if (identical(appGoRouter, router)) appGoRouter = null;
  });
  return router;
});

class _RouteErrorScreen extends StatelessWidget {
  const _RouteErrorScreen({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_off_rounded, size: 48),
              const SizedBox(height: 16),
              Text(
                "That screen doesn't exist",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                message ?? '',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go(Routes.today),
                child: const Text('Back to Today'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
