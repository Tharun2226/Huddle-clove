import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/di/providers.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/utils/app_feedback.dart';
import '../../../../shared/utils/formatters.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../domain/meeting.dart';
import '../../domain/task.dart';
import 'create_meeting_sheet.dart';

/// Meeting details sheet with optional edit/delete for managers.
Future<void> showMeetingSheet(
  BuildContext context,
  WidgetRef ref,
  Meeting meeting, {
  Task? task,
  bool canManage = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _MeetingSheet(
      meeting: meeting,
      task: task,
      canManage: canManage,
    ),
  );
}

const _linksChannel = MethodChannel('huddle/links');

Uri? _meetingUri(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  return Uri.tryParse(withScheme);
}

class _MeetingSheet extends ConsumerWidget {
  const _MeetingSheet({
    required this.meeting,
    this.task,
    this.canManage = false,
  });

  final Meeting meeting;
  final Task? task;
  final bool canManage;

  Future<void> _join(BuildContext context) async {
    if (!meeting.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This is an in-person meeting')),
      );
      return;
    }
    final uri = _meetingUri(meeting.link);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No meeting link was added')),
      );
      return;
    }
    try {
      await _linksChannel.invokeMethod<bool>('openUrl', uri.toString());
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the meeting link')),
      );
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    Navigator.of(context).pop();
    await showCreateMeetingSheet(
      context,
      ref,
      task: task,
      meeting: meeting,
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this meeting?'),
        content: Text(
          '“${meeting.title}” will be removed for everyone. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: palette.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(taskRepositoryProvider).deleteMeeting(meeting.id);
      if (!context.mounted) return;
      AppFeedback.successAndPop(
        context,
        message: 'Meeting deleted',
      );
    } catch (e) {
      if (!context.mounted) return;
      AppFeedback.error(
        AppFeedback.messengerOf(context),
        AppFeedback.apiMessage(e, 'Could not delete meeting'),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final scheme = context.colors;
    final directory = ref.watch(teamById);
    final me = ref.watch(currentUserProvider);
    final attendees = meeting.attendeeIds.map(directory.resolve).toList();
    final hasLink = meeting.isOnline && meeting.link.trim().isNotEmpty;
    final guests = meeting.isOnline
        ? const <ExternalAttendee>[]
        : meeting.externalAttendees;
    // Only show manage menu when explicitly allowed (Tasks / task detail),
    // not on Today / home.
    final manage = canManage;

    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Insets.screen,
            0,
            Insets.screen,
            Insets.screen,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Insets.md,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: meeting.isLive
                        ? palette.successContainer
                        : scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Text(
                    meeting.isLive
                        ? 'HAPPENING NOW'
                        : Fmt.startsIn(meeting.start, end: meeting.end).toUpperCase(),
                    style: context.text.labelSmall?.copyWith(
                      color: meeting.isLive ? palette.success : scheme.primary,
                    ),
                  ),
                ),
                const Spacer(),
                if (manage)
                  PopupMenuButton<String>(
                    tooltip: 'Meeting actions',
                    padding: EdgeInsets.zero,
                    splashRadius: 20,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: palette.neutral,
                    ),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _edit(context, ref);
                      } else if (value == 'delete') {
                        _delete(context, ref);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        height: 40,
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        height: 40,
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: palette.danger,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Delete',
                              style: TextStyle(color: palette.danger),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: Insets.lg),
            Text(meeting.title, style: context.text.headlineSmall),
            const SizedBox(height: Insets.sm),
            Text(
              meeting.isOnline ? 'Online meeting' : 'In-person meeting',
              style: context.text.bodySmall?.copyWith(color: palette.neutral),
            ),
            const SizedBox(height: Insets.lg),
            _Row(
              icon: Icons.schedule_rounded,
              label: Fmt.timeRange(meeting.start, meeting.end),
              sub:
                  '${Fmt.friendlyDate(meeting.start)} · ${Fmt.duration(meeting.duration)}',
            ),
            if (meeting.location.isNotEmpty) ...[
              const SizedBox(height: Insets.md),
              _Row(icon: Icons.place_rounded, label: meeting.location),
            ],
            if (hasLink) ...[
              const SizedBox(height: Insets.md),
              _Row(
                icon: Icons.link_rounded,
                label: meeting.link.trim(),
                sub: 'Tap Join to open',
              ),
            ],
            if (meeting.notes.isNotEmpty) ...[
              const SizedBox(height: Insets.md),
              _Row(icon: Icons.notes_rounded, label: meeting.notes),
            ],
            if (meeting.recurrence != MeetingRecurrence.none) ...[
              const SizedBox(height: Insets.md),
              _Row(
                icon: Icons.repeat_rounded,
                label: meeting.recurrenceSummary,
              ),
            ],
            if (meeting.taskId != null) ...[
              const SizedBox(height: Insets.md),
              _Row(
                icon: Icons.task_alt_rounded,
                label: task?.title ?? 'Linked to a task',
                sub: 'Opens from the related task',
              ),
            ],
            const SizedBox(height: Insets.xl),
            Text(
              'ATTENDEES (${meeting.isOnline ? attendees.length : guests.length})',
              style: context.text.labelSmall?.copyWith(color: palette.neutral),
            ),
            const SizedBox(height: Insets.md),
            if (meeting.isOnline)
              for (final person in attendees)
                Padding(
                  padding: const EdgeInsets.only(bottom: Insets.md),
                  child: Row(
                    children: [
                      UserAvatar(
                        user: person,
                        size: 34,
                        showRing: person.id == me.id,
                      ),
                      const SizedBox(width: Insets.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              person.id == me.id
                                  ? '${person.name} (You)'
                                  : person.name,
                              style: context.text.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              person.roleNames.isNotEmpty
                                  ? person.roleNames.first
                                  : person.role.label,
                              style: context.text.bodySmall?.copyWith(
                                color: palette.neutral,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
            else
              for (final guest in guests)
                Padding(
                  padding: const EdgeInsets.only(bottom: Insets.md),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 17,
                        backgroundColor:
                            scheme.primary.withValues(alpha: 0.12),
                        child: Icon(
                          Icons.person_outline,
                          size: 18,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: Insets.md),
                      Expanded(
                        child: Text(
                          guest.name,
                          style: context.text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            const SizedBox(height: Insets.sm),
            if (meeting.isOnline)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: hasLink ? () => _join(context) : null,
                  icon: const Icon(Icons.videocam_rounded, size: 18),
                  label: Text(hasLink ? 'Join meeting' : 'No link added'),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, this.sub});

  final IconData icon;
  final String label;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: palette.neutral),
        const SizedBox(width: Insets.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: context.text.bodyMedium),
              if (sub != null)
                Text(
                  sub!,
                  style: context.text.bodySmall?.copyWith(color: palette.neutral),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
