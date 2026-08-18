import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/router/app_router.dart';
import '../data/notification_api.dart';
import '../domain/app_notification.dart';
import '../services/push_notification_service.dart';

final notificationApiProvider = Provider<NotificationApi>(
  (ref) => NotificationApi(ref.watch(apiClientProvider)),
);

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  final service = PushNotificationService();
  ref.onDispose(() {});
  return service;
});

final notificationsProvider =
    FutureProvider.autoDispose<NotificationListResult>((ref) async {
  return ref.watch(notificationApiProvider).list();
});

final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(notificationsProvider).maybeWhen(
        data: (d) => d.unreadCount,
        orElse: () => 0,
      );
});

/// Register FCM after login and wire deep-link taps into go_router.
Future<void> bootstrapPushNotifications(WidgetRef ref) async {
  final push = ref.read(pushNotificationServiceProvider);
  final api = ref.read(notificationApiProvider);

  push.onTap = ({
    required NotificationType type,
    String? referenceId,
    String? notificationId,
    String? referenceKind,
  }) {
    _navigateWhenReady(
      type: type,
      referenceId: referenceId,
      referenceKind: referenceKind,
    );
    if (notificationId != null && notificationId.isNotEmpty) {
      api.markRead(notificationId).then((_) {
        ref.invalidate(notificationsProvider);
      }).catchError((_) {});
    }
  };

  final ok = await push.ensureInitialized();
  if (!ok) return;

  await push.requestPermissionAndRegister((token) async {
    await api.registerDevice(deviceToken: token, platform: 'android');
  });

  // Flush cold-start / early taps now that the callback is wired.
  push.flushPendingTap();
  if (PendingNotificationNav.hasPending) {
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      push.flushPendingTap();
    });
  }
}

void _navigateWhenReady({
  required NotificationType type,
  String? referenceId,
  String? referenceKind,
}) {
  void attempt([int tries = 0]) {
    final router = appGoRouter;
    if (router == null) {
      if (tries < 20) {
        Future<void>.delayed(
          const Duration(milliseconds: 150),
          () => attempt(tries + 1),
        );
      }
      return;
    }
    navigateFromNotification(
      router,
      type: type,
      referenceId: referenceId,
      referenceKind: referenceKind,
    );
  }

  attempt();
}

/// Open the screen for an in-app or push notification.
/// Uses [GoRouter.go] so nested shell routes (task/expense detail) resolve
/// correctly from the notifications stack.
void navigateFromNotification(
  GoRouter router, {
  required NotificationType type,
  String? referenceId,
  String? referenceKind,
}) {
  final id = referenceId?.trim();
  final kind = (referenceKind ?? '').trim().toLowerCase();
  final hasId = id != null && id.isNotEmpty;

  // Prefer explicit kind (covers SYSTEM_ALERT reimbursements + reminders).
  if (hasId) {
    switch (kind) {
      case 'expense':
        router.go(Routes.expenseDetail(id));
        return;
      case 'task':
        router.go(Routes.taskDetail(id));
        return;
      case 'meeting':
        router.go(Routes.today);
        return;
    }
  }

  switch (type) {
    case NotificationType.expenseApproved:
    case NotificationType.expenseRejected:
    case NotificationType.expenseSubmitted:
    case NotificationType.expenseComment:
      router.go(hasId ? Routes.expenseDetail(id) : Routes.expenses);
      return;
    case NotificationType.reminder:
      if (kind == 'meeting') {
        router.go(Routes.today);
      } else {
        router.go(hasId ? Routes.taskDetail(id!) : Routes.tasks);
      }
      return;
    case NotificationType.announcement:
    case NotificationType.systemAlert:
    case NotificationType.unknown:
      // Heuristic: expense-shaped alerts often only have referenceId.
      if (hasId && type == NotificationType.systemAlert) {
        router.go(Routes.expenseDetail(id));
        return;
      }
      if (router.state.uri.path != Routes.notifications) {
        router.go(Routes.notifications);
      }
  }
}
