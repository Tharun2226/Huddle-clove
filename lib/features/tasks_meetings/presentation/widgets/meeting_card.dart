import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/utils/formatters.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/huddle_card.dart';
import '../../domain/meeting.dart';

/// The hero card at the top of Today. It is the only saturated surface in the
/// app — that is what makes "what's next" impossible to miss.
class NextMeetingCard extends ConsumerWidget {
  const NextMeetingCard({
    super.key,
    required this.meeting,
    this.onTap,
    this.dimmed = false,
  });

  final Meeting meeting;
  final VoidCallback? onTap;
  final bool dimmed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = context.colors;
    final directory = ref.watch(teamById);
    final attendees = meeting.attendeeIds.map(directory.resolve).toList();
    final live = meeting.isLive;
    final past = meeting.isPast && !live;

    return Opacity(
      opacity: dimmed || past ? 0.72 : 1,
      child: HuddleCard(
        onTap: onTap,
        color: past ? scheme.primary.withValues(alpha: 0.75) : scheme.primary,
        borderColor: Colors.transparent,
        padding: const EdgeInsets.fromLTRB(
          Insets.lg,
          Insets.md,
          Insets.lg,
          Insets.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Flexible(
                  child: _Badge(live: live, meeting: meeting, past: past),
                ),
                const SizedBox(width: Insets.sm),
                Icon(
                  Icons.arrow_outward_rounded,
                  size: 18,
                  color: scheme.onPrimary.withValues(alpha: 0.7),
                ),
              ],
            ),
            const SizedBox(height: Insets.sm),
            Text(
              Fmt.time(meeting.start),
              style: context.text.titleLarge?.copyWith(
                color: scheme.onPrimary,
                height: 1.05,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              meeting.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.titleSmall?.copyWith(
                color: scheme.onPrimary.withValues(alpha: 0.92),
              ),
            ),
            const SizedBox(height: Insets.sm),
            Row(
              children: [
                if (attendees.isNotEmpty) ...[
                  AvatarStack(
                    users: attendees,
                    size: 22,
                    borderColor: scheme.onPrimary.withValues(alpha: 0.35),
                  ),
                  const SizedBox(width: Insets.sm),
                ],
                Expanded(
                  child: Text(
                    _subtitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: scheme.onPrimary.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final total = meeting.isOnline
        ? meeting.attendeeIds.length
        : meeting.externalAttendees.length;
    final people = '$total ${total == 1 ? 'attendee' : 'attendees'}';
    final duration = Fmt.duration(meeting.duration);
    if (meeting.location.isEmpty) return '$people · $duration';
    return '$people · $duration · ${meeting.location}';
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.live,
    required this.meeting,
    this.past = false,
  });

  final bool live;
  final Meeting meeting;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final palette = context.palette;
    final badgeFg = live ? Colors.white : scheme.onPrimary;
    final badgeBg = live
        ? palette.success
        : scheme.onPrimary.withValues(alpha: 0.16);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 4),
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[
            _LivePulse(color: badgeFg),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              live
                  ? 'HAPPENING NOW'
                  : past
                      ? 'DONE · ${Fmt.time(meeting.start).toUpperCase()}'
                      : 'NEXT · ${Fmt.startsIn(meeting.start, end: meeting.end).toUpperCase()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(
                color: badgeFg,
                fontWeight: live ? FontWeight.w700 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Breathing dot for a meeting that is already underway.
class _LivePulse extends StatefulWidget {
  const _LivePulse({required this.color});

  final Color color;

  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Compact meeting row for the agenda timeline and the Tasks screen's meeting
/// section.
class MeetingRow extends ConsumerWidget {
  const MeetingRow({
    super.key,
    required this.meeting,
    this.onTap,
    this.trailing,
  });

  final Meeting meeting;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final scheme = context.colors;
    final directory = ref.watch(teamById);
    final attendees = meeting.attendeeIds.map(directory.resolve).toList();
    final dim = meeting.isPast;

    return HuddleCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.md,
        vertical: Insets.md,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (dim ? palette.neutral : scheme.primary).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.videocam_rounded,
              size: 20,
              color: dim ? palette.neutral : scheme.primary,
            ),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  meeting.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: dim ? palette.neutral : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  Fmt.timeRange(meeting.start, meeting.end),
                  style: context.text.labelMedium?.copyWith(
                    color: palette.neutral,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (attendees.isNotEmpty) ...[
            AvatarStack(users: attendees, size: 22, max: 3),
            if (trailing != null) const SizedBox(width: Insets.xs),
          ],
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
