import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/config/org_config.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/widgets/agenda_date_picker.dart';
import '../../../tasks_meetings/presentation/providers/task_providers.dart';
import 'today_share_export.dart';

Future<void> showTodayShareSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => const _TodayShareSheet(),
  );
}

class _TodayShareSheet extends ConsumerStatefulWidget {
  const _TodayShareSheet();

  @override
  ConsumerState<_TodayShareSheet> createState() => _TodayShareSheetState();
}

class _TodayShareSheetState extends ConsumerState<_TodayShareSheet> {
  bool _busy = false;

  TodayShareData _data() {
    final me = ref.read(currentUserProvider);
    final directory = ref.read(teamById);
    final agendaDate = ref.read(todayAgendaDateProvider);
    return TodayShareData(
      userName: me.name,
      date: agendaDate,
      meetings: ref.read(todayMeetingsProvider),
      dueToday: ref.read(tasksDueTodayProvider),
      overdue: ref.read(overdueTasksProvider),
      timeline: ref.read(todayTimelineProvider),
      nextMeeting: ref.read(nextMeetingProvider),
      showTags: ref.read(orgConfigProvider).showTags,
      peopleNames: {
        for (final entry in directory.entries) entry.key: entry.value.name,
      },
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.screen,
          0,
          Insets.screen,
          Insets.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Share Today', style: context.text.titleLarge),
            const SizedBox(height: Insets.xs),
            Text(
              'Export an organized snapshot of meetings and tasks.',
              style: context.text.bodyMedium?.copyWith(color: palette.neutral),
            ),
            const SizedBox(height: Insets.lg),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Insets.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: palette.successContainer,
                  child: Icon(Icons.table_chart_rounded, color: palette.success),
                ),
                title: const Text('Share as Excel'),
                subtitle: Text(
                  'Meetings, due today, and overdue with full details',
                  style: context.text.bodySmall?.copyWith(color: palette.neutral),
                ),
                onTap: () => _run(() => shareTodayAsExcel(_data())),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: context.colors.primary.withValues(alpha: 0.12),
                  child: Icon(
                    Icons.image_rounded,
                    color: context.colors.primary,
                  ),
                ),
                title: const Text('Share as PNG'),
                subtitle: Text(
                  'Schedule table — meetings on top, tasks below',
                  style: context.text.bodySmall?.copyWith(color: palette.neutral),
                ),
                onTap: () => _run(() => shareTodayAsPng(context, _data())),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
