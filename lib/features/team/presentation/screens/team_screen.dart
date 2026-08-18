import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/domain/app_user.dart';
import '../../../../core/auth/session_controller.dart';
import '../../../../core/router/app_router.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/utils/formatters.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/huddle_card.dart';
import '../../../../shared/widgets/pill.dart';
import '../../../expenses/presentation/providers/expense_providers.dart';
import '../../../expenses/presentation/widgets/expense_card.dart';
import '../../../tasks_meetings/domain/task.dart';
import '../../../tasks_meetings/presentation/providers/task_providers.dart';
import '../../../tasks_meetings/presentation/widgets/task_visuals.dart';
import '../widgets/activity_feed.dart';
import '../widgets/team_manage_sheets.dart';

/// Manager-only. Roster, board, approvals, and activity in one place.
class TeamScreen extends ConsumerStatefulWidget {
  const TeamScreen({super.key});

  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_handleTabChange);
  }

  void _handleTabChange() {
    if (mounted && !_tabs.indexIsChanging) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_handleTabChange);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final me = ref.watch(currentUserProvider);
    final canCreateUser = me.isManager;
    final canManageOrg = me.isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Team'),
        actions: [
          if (canManageOrg)
            IconButton(
              tooltip: 'Organization settings',
              onPressed: () => context.push(Routes.orgSettings),
              icon: const Icon(Icons.settings_rounded),
            ),
          if (canCreateUser)
            IconButton(
              tooltip: 'Create user',
              onPressed: () => showCreateUserSheet(context, ref),
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: palette.hairline,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: context.text.labelLarge,
              unselectedLabelColor: palette.neutral,
              tabs: [
                const Tab(text: 'People'),
                const Tab(text: 'Board'),
                const Tab(text: 'Approvals'),
                const Tab(text: 'Activity'),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: canCreateUser
          ? FloatingActionButton.extended(
              onPressed: () => showCreateUserSheet(context, ref),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Create user'),
            )
          : null,
      body: switch (_tabs.index) {
        0 => const _PeopleRoster(),
        1 => const _TeamBoard(),
        2 => const _ApprovalQueue(),
        _ => const ActivityFeed(),
      },
    );
  }
}

class _PeopleRoster extends ConsumerWidget {
  const _PeopleRoster();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(teamProvider);
    final me = ref.watch(currentUserProvider);
    final palette = context.palette;
    final loading =
        ref.watch(remoteTeamProvider).isLoading && team.length <= 1;

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(remoteTeamProvider);
        await ref.read(remoteTeamProvider.future);
      },
      child: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(
          Insets.screen,
          Insets.lg,
          Insets.screen,
          Insets.xxl * 3,
        ),
        children: [
          Text(
            me.isAdmin ? 'Organization roster' : 'Your team',
            style: context.text.titleMedium,
          ),
          const SizedBox(height: Insets.xs),
          Text(
            me.isAdmin
                ? 'Manage people and their roles. Assign members to a manager so that manager can see their work.'
                : team.length <= 1
                    ? 'No direct reports yet. Create a member and they will report to you, or ask an admin to reassign people.'
                    : 'People who report to you.',
            style: context.text.bodyMedium?.copyWith(color: palette.neutral),
          ),
          const SizedBox(height: Insets.lg),
          for (final person in team) ...[
          HuddleCard(
            padding: const EdgeInsets.all(Insets.md),
            child: Row(
              children: [
                UserAvatar(
                  user: person,
                  size: 44,
                  showRing: person.id == me.id,
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.id == me.id ? '${person.name} (you)' : person.name,
                        style: context.text.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (person.title.isNotEmpty) person.title,
                          person.email,
                          if (person.managerName != null &&
                              person.managerName!.isNotEmpty)
                            'Manager: ${person.managerName}',
                        ].join(' · '),
                        style: context.text.bodySmall?.copyWith(
                          color: palette.neutral,
                        ),
                      ),
                    ],
                  ),
                ),
                Pill(
                  label: person.roleNames.isNotEmpty
                      ? person.roleNames.first
                      : person.role.label,
                  color: person.isManager ? palette.info : palette.neutral,
                  dense: true,
                ),
                if (me.isAdmin) ...[
                  const SizedBox(width: Insets.xs),
                  IconButton(
                    tooltip: 'Change role',
                    onPressed: () => showChangeRoleSheet(
                      context,
                      ref,
                      person: person,
                    ),
                    icon: const Icon(Icons.manage_accounts_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Insets.md),
        ],
      ],
      ),
    );
  }
}

class _TeamBoard extends ConsumerWidget {
  const _TeamBoard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(teamProvider);
    final tasks = ref.watch(visibleTasksProvider);

    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(
        Insets.screen,
        Insets.lg,
        Insets.screen,
        Insets.xxl * 2,
      ),
      children: [
        for (final person in team) ...[
          _PersonLane(
            person: person,
            tasks: tasks.where((t) => t.assigneeId == person.id).toList(),
          ),
          const SizedBox(height: Insets.lg),
        ],
      ],
    );
  }
}

class _PersonLane extends ConsumerWidget {
  const _PersonLane({required this.person, required this.tasks});

  final AppUser person;
  final List<Task> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final me = ref.watch(currentUserProvider);
    final open = tasks.where((t) => !t.isDone).toList();
    final done = tasks.length - open.length;
    final overdue = tasks.where((t) => t.isOverdue).length;

    return HuddleCard(
      padding: const EdgeInsets.all(Insets.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(Insets.xs),
            child: Row(
              children: [
                UserAvatar(user: person, size: 38, showRing: person.id == me.id),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        person.id == me.id ? 'You' : person.name,
                        style: context.text.titleSmall,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        person.title,
                        style: context.text.bodySmall?.copyWith(
                          color: palette.neutral,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Assign a task to ${person.firstName}',
                  onPressed: () =>
                      context.push('${Routes.newTask}?assignee=${person.id}'),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.sm),
          Row(
            children: [
              Pill(
                label: '${open.length} open',
                color: open.isEmpty ? palette.neutral : palette.info,
                dense: true,
              ),
              const SizedBox(width: Insets.sm),
              if (overdue > 0) ...[
                Pill(
                  label: '$overdue overdue',
                  color: palette.danger,
                  dense: true,
                ),
                const SizedBox(width: Insets.sm),
              ],
              Pill(label: '$done done', color: palette.success, dense: true),
            ],
          ),
          if (open.isNotEmpty) ...[
            const SizedBox(height: Insets.md),
            Divider(height: 1, color: palette.hairline),
            const SizedBox(height: Insets.md),
            for (final task in open.take(3)) ...[
              _LaneRow(task: task),
              if (task != open.take(3).last) const SizedBox(height: Insets.sm),
            ],
            if (open.length > 3) ...[
              const SizedBox(height: Insets.sm),
              TextButton(
                onPressed: () {
                  ref.read(taskFilterProvider.notifier).setAssignee(person.id);
                  context.go(Routes.tasks);
                },
                child: Text('View all ${open.length} tasks'),
              ),
            ],
          ] else ...[
            const SizedBox(height: Insets.md),
            Padding(
              padding: const EdgeInsets.only(left: Insets.xs, bottom: Insets.sm),
              child: Text(
                'Nothing open right now.',
                style: context.text.bodySmall?.copyWith(color: palette.neutral),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LaneRow extends StatelessWidget {
  const _LaneRow({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return InkWell(
      onTap: () => context.push(Routes.taskDetail(task.id)),
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.xs,
          vertical: Insets.sm,
        ),
        child: Row(
          children: [
            Dot(color: task.priority.color(palette)),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: Insets.sm),
            if (task.dueDate != null)
              Text(
                Fmt.friendlyDate(task.dueDate!),
                style: context.text.labelSmall?.copyWith(
                  letterSpacing: 0,
                  fontWeight: FontWeight.w500,
                  color: task.isOverdue ? palette.danger : palette.neutral,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ApprovalQueue extends ConsumerWidget {
  const _ApprovalQueue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final approvals = ref.watch(pendingApprovalsProvider);
    final awaiting = ref.watch(awaitingReimbursementProvider);

    if (approvals.isEmpty && awaiting.isEmpty) {
      return const EmptyState(
        icon: Icons.inbox_rounded,
        title: 'Queue is clear',
        message: 'Nothing is waiting on your decision.',
      );
    }

    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(
        Insets.screen,
        Insets.lg,
        Insets.screen,
        Insets.xxl * 2,
      ),
      children: [
        if (approvals.isNotEmpty) ...[
          SectionHeader(title: 'Needs your decision', count: approvals.length),
          for (final expense in approvals) ...[
            ExpenseCard(
              expense: expense,
              showSubmitter: true,
              onTap: () => context.push(Routes.expenseDetail(expense.id)),
            ),
            const SizedBox(height: Insets.md),
          ],
          const SizedBox(height: Insets.lg),
        ],
        if (awaiting.isNotEmpty) ...[
          SectionHeader(title: 'Approved, awaiting payout', count: awaiting.length),
          for (final expense in awaiting) ...[
            ExpenseCard(
              expense: expense,
              showSubmitter: true,
              onTap: () => context.push(Routes.expenseDetail(expense.id)),
            ),
            const SizedBox(height: Insets.md),
          ],
        ],
      ],
    );
  }
}
