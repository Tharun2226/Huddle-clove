import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/theme/app_tokens.dart';
import '../../../shared/utils/app_feedback.dart';
import '../../../shared/utils/formatters.dart';
import '../domain/app_notification.dart';
import '../providers/notification_providers.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    final palette = context.palette;
    final hasItems = async.maybeWhen(
      data: (d) => d.items.isNotEmpty,
      orElse: () => false,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (hasItems)
            TextButton(
              onPressed: () => _confirmClearAll(context, ref),
              child: Text(
                'Clear all',
                style: context.text.labelLarge?.copyWith(
                  color: palette.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(
            'Could not load notifications',
            style: context.text.bodyMedium?.copyWith(color: palette.neutral),
          ),
        ),
        data: (data) {
          if (data.items.isEmpty) {
            return Center(
              child: Text(
                'No notifications yet',
                style: context.text.bodyLarge?.copyWith(color: palette.neutral),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(notificationsProvider);
              await ref.read(notificationsProvider.future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: Insets.md),
              itemCount: data.items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final n = data.items[index];
                return Dismissible(
                  key: ValueKey(n.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: palette.danger,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: Insets.lg),
                    child: const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  onDismissed: (_) async {
                    await ref.read(notificationApiProvider).delete(n.id);
                    ref.invalidate(notificationsProvider);
                  },
                  child: ListTile(
                    leading: Icon(
                      n.isRead
                          ? Icons.notifications_none_rounded
                          : Icons.notifications_active_rounded,
                      color: n.isRead ? palette.neutral : context.colors.primary,
                    ),
                    title: Text(
                      n.title,
                      style: context.text.titleSmall?.copyWith(
                        fontWeight:
                            n.isRead ? FontWeight.w500 : FontWeight.w700,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(n.body),
                        const SizedBox(height: 4),
                        Text(
                          Fmt.friendlyDate(n.createdAt),
                          style: context.text.bodySmall?.copyWith(
                            color: palette.neutral,
                          ),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                    onTap: () => _onNotificationTap(context, ref, n),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _onNotificationTap(
    BuildContext context,
    WidgetRef ref,
    AppNotification n,
  ) async {
    // Navigate first — invalidate can rebuild and drop the tap mid-flight.
    final router = GoRouter.of(context);
    navigateFromNotification(
      router,
      type: n.type,
      referenceId: n.referenceId,
      referenceKind: n.referenceKind,
    );

    if (!n.isRead) {
      try {
        await ref.read(notificationApiProvider).markRead(n.id);
        ref.invalidate(notificationsProvider);
      } catch (_) {
        // Navigation already happened; ignore mark-read failures.
      }
    }
  }

  Future<void> _confirmClearAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all notifications?'),
        content: const Text(
          'This permanently removes every notification from your inbox.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(notificationApiProvider).clearAll();
      ref.invalidate(notificationsProvider);
      if (!context.mounted) return;
      AppFeedback.success(
        AppFeedback.messengerOf(context),
        'All notifications cleared',
      );
    } catch (e) {
      if (!context.mounted) return;
      AppFeedback.error(
        AppFeedback.messengerOf(context),
        AppFeedback.apiMessage(e, 'Could not clear notifications'),
      );
    }
  }
}
