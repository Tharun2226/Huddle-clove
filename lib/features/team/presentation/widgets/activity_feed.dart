import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/utils/formatters.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/huddle_card.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../../domain/activity_event.dart';

final activityProvider = StreamProvider<List<ActivityEvent>>(
  (ref) => ref.watch(activityRepositoryProvider).watchActivity(),
);

/// Chronological team feed: "Aisha completed task X", "Rahul submitted ₹1,200".
/// Grouped by day so a long feed stays scannable.
class ActivityFeed extends ConsumerWidget {
  const ActivityFeed({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(activityProvider);

    return activityAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(Insets.screen),
        child: SkeletonList(count: 5, height: 64),
      ),
      error: (error, _) => EmptyState(
        icon: Icons.error_outline_rounded,
        title: "Couldn't load activity",
        message: '$error',
      ),
      data: (events) {
        if (events.isEmpty) {
          return const EmptyState(
            icon: Icons.timeline_rounded,
            title: 'No activity yet',
            message: 'Task and expense updates will show up here.',
          );
        }

        final grouped = _groupByDay(events);

        return ListView.builder(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(
            Insets.screen,
            Insets.lg,
            Insets.screen,
            Insets.xxl * 2,
          ),
          itemCount: grouped.length,
          itemBuilder: (context, index) {
            final (day, dayEvents) = grouped[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (index > 0) const SizedBox(height: Insets.lg),
                Padding(
                  padding: const EdgeInsets.only(
                    left: Insets.xs,
                    bottom: Insets.md,
                  ),
                  child: Text(
                    Fmt.friendlyDate(day).toUpperCase(),
                    style: context.text.labelSmall?.copyWith(
                      color: context.palette.neutral,
                    ),
                  ),
                ),
                for (final event in dayEvents) ...[
                  _ActivityTile(event: event),
                  const SizedBox(height: Insets.md),
                ],
              ],
            );
          },
        );
      },
    );
  }

  List<(DateTime, List<ActivityEvent>)> _groupByDay(List<ActivityEvent> events) {
    final groups = <DateTime, List<ActivityEvent>>{};
    for (final event in events) {
      final day = DateTime(event.at.year, event.at.month, event.at.day);
      groups.putIfAbsent(day, () => []).add(event);
    }
    final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final day in days) (day, groups[day]!)];
  }
}

class _ActivityTile extends ConsumerWidget {
  const _ActivityTile({required this.event});

  final ActivityEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final directory = ref.watch(teamById);
    final me = ref.watch(currentUserProvider);
    final actor = directory.resolve(event.actorId);
    final visual = _visualFor(event.type, palette);

    return HuddleCard(
      onTap: _destination() == null ? null : () => context.push(_destination()!),
      padding: const EdgeInsets.all(Insets.md),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              UserAvatar(user: actor, size: 36),
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: visual.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.card, width: 1.8),
                  ),
                  child: Icon(visual.icon, size: 9, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                RichText(
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: context.text.bodyMedium,
                    children: [
                      TextSpan(
                        text: actor.id == me.id ? 'You' : actor.firstName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: ' ${visual.verb} '),
                      if (event.amount != null)
                        TextSpan(
                          text: '${Fmt.money(event.amount!)} ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      TextSpan(
                        text: event.subject,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  Fmt.relative(event.at),
                  style: context.text.labelSmall?.copyWith(
                    color: palette.neutral,
                    letterSpacing: 0,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _destination() {
    final id = event.targetId;
    if (id == null) return null;
    return switch (event.type) {
      ActivityType.taskCreated ||
      ActivityType.taskCompleted ||
      ActivityType.taskMoved ||
      ActivityType.taskCommented => Routes.taskDetail(id),
      ActivityType.expenseSubmitted ||
      ActivityType.expenseApproved ||
      ActivityType.expenseRejected ||
      ActivityType.expenseReimbursed => Routes.expenseDetail(id),
      ActivityType.meetingScheduled => null,
    };
  }

  ({Color color, IconData icon, String verb}) _visualFor(
    ActivityType type,
    AppPalette palette,
  ) {
    return switch (type) {
      ActivityType.taskCreated => (
        color: palette.info,
        icon: Icons.add_rounded,
        verb: 'created',
      ),
      ActivityType.taskCompleted => (
        color: palette.success,
        icon: Icons.check_rounded,
        verb: 'completed',
      ),
      ActivityType.taskMoved => (
        color: palette.warning,
        icon: Icons.swap_horiz_rounded,
        verb: 'moved',
      ),
      ActivityType.taskCommented => (
        color: palette.neutral,
        icon: Icons.mode_comment_rounded,
        verb: 'commented on',
      ),
      ActivityType.expenseSubmitted => (
        color: palette.warning,
        icon: Icons.upload_rounded,
        verb: 'submitted',
      ),
      ActivityType.expenseApproved => (
        color: palette.success,
        icon: Icons.check_rounded,
        verb: 'approved',
      ),
      ActivityType.expenseRejected => (
        color: palette.danger,
        icon: Icons.close_rounded,
        verb: 'rejected',
      ),
      ActivityType.expenseReimbursed => (
        color: palette.success,
        icon: Icons.payments_rounded,
        verb: 'reimbursed',
      ),
      ActivityType.meetingScheduled => (
        color: palette.info,
        icon: Icons.event_rounded,
        verb: 'scheduled',
      ),
    };
  }
}
