import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/router/app_router.dart';
import '../../../shared/theme/app_tokens.dart';
import '../../../shared/utils/formatters.dart';
import '../../../shared/widgets/agenda_date_picker.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/huddle_card.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../notifications/presentation/notification_bell.dart';
import '../../tasks_meetings/domain/meeting.dart';
import '../../tasks_meetings/domain/task.dart';
import '../../tasks_meetings/presentation/providers/task_providers.dart';
import '../../tasks_meetings/presentation/widgets/meeting_card.dart';
import '../../tasks_meetings/presentation/widgets/meeting_sheet.dart';
import '../../tasks_meetings/presentation/widgets/task_card.dart';
import '../../tasks_meetings/presentation/widgets/task_import_excel.dart';
import 'widgets/stat_tile.dart';
import 'widgets/today_share_sheet.dart';

enum TodayScheduleFilter { all, dueToday, overdue }

class TodayScheduleFilterController extends Notifier<TodayScheduleFilter> {
  @override
  TodayScheduleFilter build() => TodayScheduleFilter.all;

  void set(TodayScheduleFilter value) => state = value;

  void clear() => state = TodayScheduleFilter.all;
}

final todayScheduleFilterProvider =
    NotifierProvider<TodayScheduleFilterController, TodayScheduleFilter>(
  TodayScheduleFilterController.new,
);

/// Module C's "Today" screen: meetings for the day, what is due, and filters.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksProvider);
    final agendaDate = ref.watch(todayAgendaDateProvider);
    final isToday = isCalendarToday(agendaDate);
    final todayMeetings = ref.watch(todayMeetingsProvider);
    final dueToday = ref.watch(tasksDueTodayProvider);
    final overdue = ref.watch(overdueTasksProvider);
    final filter = ref.watch(todayScheduleFilterProvider);
    final timeline = ref.watch(todayTimelineProvider);
    final loading = tasksAsync.isLoading && !tasksAsync.hasValue;
    final hasError = tasksAsync.hasError && !tasksAsync.hasValue;

    final scheduleItems = _scheduleForFilter(
      filter: filter,
      timeline: timeline,
      dueToday: dueToday,
      overdue: overdue,
    );

    final dayLabel = isToday ? 'Today' : Fmt.friendlyDate(agendaDate);
    final scheduleTitle = switch (filter) {
      TodayScheduleFilter.all =>
        isToday ? "Today's schedule" : '$dayLabel schedule',
      TodayScheduleFilter.dueToday =>
        isToday ? 'Due today' : 'Due $dayLabel',
      TodayScheduleFilter.overdue => 'Overdue',
    };

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.newTaskWithDue(agendaDate)),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add task'),
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(tasksProvider);
            ref.invalidate(meetingsProvider);
            await Future<void>.delayed(const Duration(milliseconds: 600));
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              const SliverToBoxAdapter(child: _Header()),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.screen,
                  Insets.sm,
                  Insets.screen,
                  Insets.xxl * 4,
                ),
                sliver: SliverList.list(
                  children: [
                    if (loading) ...[
                      const SkeletonCard(height: 150),
                      const SizedBox(height: Insets.xl),
                      const SkeletonList(count: 3),
                    ] else if (hasError) ...[
                      HuddleCard(
                        child: EmptyState(
                          compact: true,
                          icon: Icons.cloud_off_rounded,
                          title: 'Couldn’t load Today',
                          message: 'Pull down to refresh, or tap Retry.',
                          action: FilledButton(
                            onPressed: () {
                              ref.invalidate(tasksProvider);
                              ref.invalidate(meetingsProvider);
                            },
                            child: const Text('Retry'),
                          ),
                        ),
                      ),
                    ] else ...[
                      AgendaDateButton(
                        date: agendaDate,
                        onPick: () => pickAgendaDate(
                          context: context,
                          initialDate: agendaDate,
                          onPicked: (d) => ref
                              .read(todayAgendaDateProvider.notifier)
                              .set(d),
                        ),
                        onToday: () => ref
                            .read(todayAgendaDateProvider.notifier)
                            .goToday(),
                      ),
                      const SizedBox(height: Insets.lg),
                      _MeetingsTodaySection(
                        meetings: todayMeetings,
                        dayLabel: dayLabel,
                        isToday: isToday,
                      ),
                      const SizedBox(height: Insets.lg),

                      _StatsRow(
                        dueToday: dueToday,
                        overdue: overdue,
                        isToday: isToday,
                        dayLabel: dayLabel,
                      ),
                      const SizedBox(height: Insets.xl),

                      if (overdue.isNotEmpty &&
                          isToday &&
                          filter != TodayScheduleFilter.overdue) ...[
                        _OverdueBanner(
                          count: overdue.length,
                          onTap: () => _openOverdue(context, ref, overdue),
                        ),
                        const SizedBox(height: Insets.xl),
                      ],

                      SectionHeader(
                        title: scheduleTitle,
                        count: scheduleItems.isEmpty ? null : scheduleItems.length,
                        action: filter == TodayScheduleFilter.all
                            ? (timeline.isEmpty
                                ? null
                                : TextButton(
                                    onPressed: () => context.go(Routes.tasks),
                                    child: const Text('See all'),
                                  ))
                            : TextButton(
                                onPressed: () => ref
                                    .read(todayScheduleFilterProvider.notifier)
                                    .clear(),
                                child: const Text('Clear'),
                              ),
                      ),
                      if (scheduleItems.isEmpty)
                        HuddleCard(
                          child: EmptyState(
                            compact: true,
                            icon: filter == TodayScheduleFilter.all
                                ? Icons.beach_access_rounded
                                : Icons.check_circle_outline_rounded,
                            title: switch (filter) {
                              TodayScheduleFilter.all =>
                                'Nothing scheduled for $dayLabel',
                              TodayScheduleFilter.dueToday =>
                                'No tasks due $dayLabel',
                              TodayScheduleFilter.overdue => 'No overdue tasks',
                            },
                            message: switch (filter) {
                              TodayScheduleFilter.all =>
                                'Pick another date, or create a meeting or task.',
                              TodayScheduleFilter.dueToday =>
                                'Tap Clear to return to the full schedule.',
                              TodayScheduleFilter.overdue =>
                                'Tap Clear to return to the full schedule.',
                            },
                          ),
                        )
                      else
                        for (final entry in scheduleItems) ...[
                          switch (entry) {
                            MeetingEntry(:final meeting) => MeetingRow(
                                meeting: meeting,
                                onTap: () =>
                                    showMeetingSheet(context, ref, meeting),
                              ),
                            TaskEntry(:final task) => TaskCard(
                                task: task,
                                onTap: () =>
                                    context.push(Routes.taskDetail(task.id)),
                              ),
                          },
                          const SizedBox(height: Insets.md),
                        ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static List<AgendaEntry> _scheduleForFilter({
    required TodayScheduleFilter filter,
    required List<AgendaEntry> timeline,
    required List<Task> dueToday,
    required List<Task> overdue,
  }) {
    switch (filter) {
      case TodayScheduleFilter.all:
        return timeline;
      case TodayScheduleFilter.dueToday:
        return [for (final t in dueToday) TaskEntry(t)];
      case TodayScheduleFilter.overdue:
        return [
          for (final t in overdue)
            if (t.dueDate != null) TaskEntry(t),
        ];
    }
  }

  static void _openOverdue(
    BuildContext context,
    WidgetRef ref,
    List<Task> overdue,
  ) {
    if (overdue.length == 1) {
      context.push(Routes.taskDetail(overdue.first.id));
      return;
    }
    ref.read(todayScheduleFilterProvider.notifier).set(
          TodayScheduleFilter.overdue,
        );
  }
}

class _MeetingsTodaySection extends ConsumerWidget {
  const _MeetingsTodaySection({
    required this.meetings,
    required this.dayLabel,
    required this.isToday,
  });

  final List<Meeting> meetings;
  final String dayLabel;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (meetings.isEmpty) {
      return _NoMeetingsCard(dayLabel: dayLabel, isToday: isToday);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: isToday ? "Today's meetings" : 'Meetings · $dayLabel',
          count: meetings.length,
        ),
        SizedBox(
          height: 156,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(right: Insets.sm),
            itemCount: meetings.length,
            separatorBuilder: (_, _) => const SizedBox(width: Insets.md),
            itemBuilder: (context, index) {
              final meeting = meetings[index];
              return SizedBox(
                width: MediaQuery.sizeOf(context).width - (Insets.screen * 2) - 28,
                child: NextMeetingCard(
                  meeting: meeting,
                  dimmed: meeting.isPast && !meeting.isLive,
                  onTap: () => showMeetingSheet(context, ref, meeting),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    final palette = context.palette;
    final agendaDate = ref.watch(todayAgendaDateProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.screen,
        Insets.lg,
        Insets.screen,
        Insets.lg,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  Fmt.weekdayLong(agendaDate).toUpperCase(),
                  style: context.text.labelSmall?.copyWith(color: palette.neutral),
                ),
                const SizedBox(height: 5),
                Text(
                  '${Fmt.greeting()}, ${me.firstName}',
                  style: context.text.headlineSmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Import tasks',
            onPressed: () => showTaskImportSheet(context, ref),
            icon: Icon(
              Icons.upload_file_rounded,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          IconButton(
            tooltip: 'Share day',
            onPressed: () => showTodayShareSheet(context, ref),
            icon: Icon(
              Icons.share_rounded,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const NotificationBell(),
          const SizedBox(width: Insets.xs),
          Semantics(
            button: true,
            label: 'Settings and profile',
            child: InkWell(
              onTap: () => context.push(Routes.settings),
              borderRadius: BorderRadius.circular(Radii.pill),
              child: UserAvatar(user: me, size: 42),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends ConsumerWidget {
  const _StatsRow({
    required this.dueToday,
    required this.overdue,
    required this.isToday,
    required this.dayLabel,
  });

  final List<Task> dueToday;
  final List<Task> overdue;
  final bool isToday;
  final String dayLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final filter = ref.watch(todayScheduleFilterProvider);

    return Row(
      children: [
        Expanded(
          child: StatTile(
            label: isToday ? 'Due today' : 'Due $dayLabel',
            value: '${dueToday.length}',
            icon: Icons.today_rounded,
            color: context.colors.primary,
            selected: filter == TodayScheduleFilter.dueToday,
            onTap: () {
              if (dueToday.isEmpty) return;
              if (dueToday.length == 1) {
                context.push(Routes.taskDetail(dueToday.first.id));
                return;
              }
              ref.read(todayScheduleFilterProvider.notifier).set(
                    filter == TodayScheduleFilter.dueToday
                        ? TodayScheduleFilter.all
                        : TodayScheduleFilter.dueToday,
                  );
            },
          ),
        ),
        const SizedBox(width: Insets.md),
        Expanded(
          child: StatTile(
            label: 'Overdue',
            value: '${overdue.length}',
            icon: Icons.error_outline_rounded,
            color: overdue.isNotEmpty ? palette.danger : palette.neutral,
            selected: filter == TodayScheduleFilter.overdue,
            onTap: !isToday
                ? null
                : () {
                    if (overdue.isEmpty) return;
                    if (overdue.length == 1) {
                      context.push(Routes.taskDetail(overdue.first.id));
                      return;
                    }
                    ref.read(todayScheduleFilterProvider.notifier).set(
                          filter == TodayScheduleFilter.overdue
                              ? TodayScheduleFilter.all
                              : TodayScheduleFilter.overdue,
                        );
                  },
          ),
        ),
      ],
    );
  }
}

class _OverdueBanner extends StatelessWidget {
  const _OverdueBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return HuddleCard(
      onTap: onTap,
      color: palette.dangerContainer,
      borderColor: palette.danger.withValues(alpha: 0.25),
      elevated: false,
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.lg,
        vertical: Insets.md,
      ),
      child: Row(
        children: [
          Icon(Icons.error_rounded, size: 18, color: palette.danger),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Text(
              count == 1
                  ? '1 task is past its due date'
                  : '$count tasks are past their due date',
              style: context.text.bodyMedium?.copyWith(
                color: palette.onDanger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: palette.danger),
        ],
      ),
    );
  }
}

class _NoMeetingsCard extends StatelessWidget {
  const _NoMeetingsCard({
    required this.dayLabel,
    required this.isToday,
  });

  final String dayLabel;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return HuddleCard(
      padding: const EdgeInsets.all(Insets.xl),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: palette.successContainer,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Icon(
              Icons.event_available_rounded,
              color: palette.success,
              size: 22,
            ),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isToday
                      ? 'No meetings today'
                      : 'No meetings on $dayLabel',
                  style: context.text.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Your calendar is clear for this day.',
                  style: context.text.bodySmall?.copyWith(color: palette.neutral),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
