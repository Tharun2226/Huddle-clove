import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/di/providers.dart';
import '../../../../core/network/api_config.dart';
import '../../../../core/router/app_router.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/utils/app_feedback.dart';
import '../../../../shared/utils/formatters.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/huddle_card.dart';
import '../../../../shared/widgets/pill.dart';
import '../../domain/expense.dart';
import '../providers/expense_providers.dart';
import '../widgets/expense_visuals.dart';
import '../widgets/receipt_viewer.dart';
import '../widgets/status_tracker.dart';

class ExpenseDetailScreen extends ConsumerWidget {
  const ExpenseDetailScreen({super.key, required this.expenseId});

  final String expenseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expense = ref.watch(expenseByIdProvider(expenseId));

    if (expense == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Expense not found',
          message: 'It may have been deleted.',
        ),
      );
    }

    final palette = context.palette;
    final me = ref.watch(currentUserProvider);
    final directory = ref.watch(teamById);
    final submitter = directory.resolve(expense.submitterId);
    final isMine = expense.submitterId == me.id;
    // Admins and managers can approve submitted expenses, including their own.
    final canDecide =
        me.canApproveExpenses && expense.status.isPendingApproval;
    final canPayOut =
        me.canApproveExpenses && expense.status == ExpenseStatus.approved;
    final canDelete = isMine && expense.status.canDeleteByOwner;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense'),
        actions: [
          if (isMine && expense.status.isEditable)
            TextButton(
              onPressed: () => context.push(Routes.newExpense, extra: expense),
              child: const Text('Edit'),
            ),
          if (canDelete)
            IconButton(
              tooltip: 'Delete',
              onPressed: () => _confirmDelete(context, ref, expense),
              icon: Icon(Icons.delete_outline_rounded, color: palette.danger),
            ),
        ],
      ),
      bottomNavigationBar: _Actions(
        expense: expense,
        canDecide: canDecide,
        canPayOut: canPayOut,
        canSubmit: isMine && expense.status.isEditable,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(
          Insets.screen,
          Insets.sm,
          Insets.screen,
          Insets.xxl,
        ),
        children: [
          HuddleCard(
            padding: const EdgeInsets.all(Insets.xl),
            child: Column(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: expense.category.color(palette).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Icon(
                    expense.category.icon,
                    size: 26,
                    color: expense.category.color(palette),
                  ),
                ),
                const SizedBox(height: Insets.lg),
                Text(
                  Fmt.moneyPrecise(expense.amount),
                  style: context.text.displaySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: Insets.xs),
                Text(
                  expense.merchant,
                  style: context.text.titleMedium?.copyWith(
                    color: palette.neutral,
                  ),
                ),
                const SizedBox(height: Insets.lg),
                Pill(
                  label: expense.status.label,
                  color: expense.status.color(palette),
                  icon: expense.status.icon,
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.xl),

          if (expense.status != ExpenseStatus.rejected) ...[
            const SectionHeader(title: 'Progress'),
            HuddleCard(child: StatusTracker(expense: expense)),
            const SizedBox(height: Insets.xl),
          ],

          if (expense.status == ExpenseStatus.rejected &&
              expense.decisionNote.isNotEmpty) ...[
            _RejectionNote(expense: expense),
            const SizedBox(height: Insets.xl),
          ],

          if (expense.breachesPolicy && !expense.status.isSettled) ...[
            _PolicyFlag(expense: expense),
            const SizedBox(height: Insets.xl),
          ],

          const SectionHeader(title: 'Details'),
          HuddleCard(
            child: Column(
              children: [
                _Row(
                  label: 'Submitted by',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserAvatar(user: submitter, size: 24),
                      const SizedBox(width: Insets.sm),
                      Text(
                        isMine ? 'You' : submitter.name,
                        style: context.text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: Insets.xl, color: palette.hairline),
                _Row(label: 'Category', value: expense.category.label),
                Divider(height: Insets.xl, color: palette.hairline),
                _Row(label: 'Date', value: Fmt.dayMonthYear(expense.date)),
                if (expense.decidedAt != null) ...[
                  Divider(height: Insets.xl, color: palette.hairline),
                  _Row(
                    label: expense.status == ExpenseStatus.rejected
                        ? 'Rejected'
                        : 'Approved',
                    value: Fmt.friendlyDate(expense.decidedAt!),
                  ),
                ],
                if (expense.reimbursedAt != null) ...[
                  Divider(height: Insets.xl, color: palette.hairline),
                  _Row(
                    label: 'Paid out',
                    value: Fmt.friendlyDate(expense.reimbursedAt!),
                  ),
                ],
                if (expense.receiptPath != null) ...[
                  Divider(height: Insets.xl, color: palette.hairline),
                  _Row(
                    label: 'Receipt',
                    child: Pill(
                      label: 'Tap to view',
                      color: palette.success,
                      icon: Icons.attachment_rounded,
                      dense: true,
                    ),
                  ),
                  const SizedBox(height: Insets.md),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => showReceiptViewer(
                        context,
                        networkUrl: ApiConfig.resolveMediaUrl(
                          expense.receiptPath,
                        ),
                      ),
                      borderRadius: BorderRadius.circular(Radii.md),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.md),
                        child: AspectRatio(
                          aspectRatio: 16 / 10,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                ApiConfig.resolveMediaUrl(expense.receiptPath),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => ColoredBox(
                                  color: palette.card,
                                  child: Center(
                                    child: Icon(
                                      Icons.receipt_long_rounded,
                                      color: palette.neutral,
                                    ),
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Padding(
                                  padding: const EdgeInsets.all(Insets.sm),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(
                                        Radii.pill,
                                      ),
                                    ),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.open_in_full_rounded,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            'View',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          if (expense.notes.isNotEmpty) ...[
            const SizedBox(height: Insets.xl),
            const SectionHeader(title: 'Notes'),
            HuddleCard(
              child: Text(
                expense.notes,
                style: context.text.bodyMedium?.copyWith(height: 1.55),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Expense expense,
  ) async {
    final palette = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: Text(
          expense.status == ExpenseStatus.submitted
              ? '${Fmt.money(expense.amount)} at ${expense.merchant} is still waiting for approval and will be removed.'
              : '${Fmt.money(expense.amount)} at ${expense.merchant} will be removed. This cannot be undone.',
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
      await ref.read(expenseRepositoryProvider).delete(expense.id);
      if (!context.mounted) return;
      AppFeedback.successAndPop(
        context,
        message: 'Expense deleted',
      );
    } catch (e) {
      if (!context.mounted) return;
      AppFeedback.error(
        AppFeedback.messengerOf(context),
        AppFeedback.apiMessage(e, 'Could not delete expense'),
      );
    }
  }
}

/// Bottom action bar. What it offers depends on role and status — a member sees
/// "Submit", a manager sees "Approve / Reject", and everyone sees nothing once
/// the expense is settled.
class _Actions extends ConsumerStatefulWidget {
  const _Actions({
    required this.expense,
    required this.canDecide,
    required this.canPayOut,
    required this.canSubmit,
  });

  final Expense expense;
  final bool canDecide;
  final bool canPayOut;
  final bool canSubmit;

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String message) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      AppFeedback.success(AppFeedback.messengerOf(context), message);
    } catch (e) {
      if (!mounted) return;
      AppFeedback.error(
        AppFeedback.messengerOf(context),
        AppFeedback.apiMessage(e, 'Action failed'),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _RejectExpenseSheet(),
    );
    if (reason == null || !mounted) return;

    final me = ref.read(currentUserProvider);
    await _run(
      () => ref
          .read(expenseRepositoryProvider)
          .reject(widget.expense.id, managerId: me.id, reason: reason),
      'Expense rejected',
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final me = ref.watch(currentUserProvider);

    final hasAction = widget.canDecide || widget.canPayOut || widget.canSubmit;
    if (!hasAction) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.fromLTRB(
        Insets.screen,
        Insets.md,
        Insets.screen,
        Insets.md + MediaQuery.viewPaddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border(top: BorderSide(color: palette.hairline)),
      ),
      child: _buildAction(context, me.id, palette),
    );
  }

  Widget _buildAction(BuildContext context, String meId, AppPalette palette) {
    if (widget.canDecide) {
      final buttonStyle = ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: Insets.md),
        ),
        visualDensity: VisualDensity.standard,
      );
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _reject,
              style: buttonStyle.copyWith(
                foregroundColor: WidgetStatePropertyAll(palette.danger),
                side: WidgetStatePropertyAll(
                  BorderSide(color: palette.danger.withValues(alpha: 0.4)),
                ),
              ),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Reject'),
            ),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => ref
                          .read(expenseRepositoryProvider)
                          .approve(widget.expense.id, managerId: meId),
                      'Expense approved',
                    ),
              style: buttonStyle.copyWith(
                backgroundColor: WidgetStatePropertyAll(palette.success),
                foregroundColor: const WidgetStatePropertyAll(Colors.white),
              ),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Approve'),
            ),
          ),
        ],
      );
    }

    if (widget.canPayOut) {
      return FilledButton.icon(
        onPressed: _busy
            ? null
            : () => _run(
                () => ref
                    .read(expenseRepositoryProvider)
                    .markReimbursed(widget.expense.id, managerId: meId),
                'Marked as reimbursed',
              ),
        icon: const Icon(Icons.payments_rounded, size: 18),
        label: const Text('Mark as reimbursed'),
      );
    }

    return FilledButton.icon(
      onPressed: _busy
          ? null
          : () async {
              if (widget.expense.status.isEditable) {
                await context.push(Routes.newExpense, extra: widget.expense);
                return;
              }
              await _run(
                () =>
                    ref.read(expenseRepositoryProvider).submit(widget.expense.id),
                'Submitted for approval',
              );
            },
      icon: Icon(
        widget.expense.status == ExpenseStatus.rejected
            ? Icons.edit_rounded
            : Icons.send_rounded,
        size: 18,
      ),
      label: Text(
        widget.expense.status == ExpenseStatus.rejected
            ? 'Fix & resubmit'
            : widget.expense.status == ExpenseStatus.draft
                ? 'Edit & submit'
                : 'Submit for approval',
      ),
    );
  }
}

class _RejectExpenseSheet extends StatefulWidget {
  const _RejectExpenseSheet();

  @override
  State<_RejectExpenseSheet> createState() => _RejectExpenseSheetState();
}

class _RejectExpenseSheetState extends State<_RejectExpenseSheet> {
  static const _presets = [
    'Missing or unclear receipt',
    'Amount exceeds policy',
    'Not a business expense',
  ];

  final _controller = TextEditingController();
  String? _selectedPreset;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _reason {
    final custom = _controller.text.trim();
    if (custom.isNotEmpty) return custom;
    return _selectedPreset?.trim() ?? '';
  }

  bool get _canSubmit => _reason.length >= 4;

  void _pickPreset(String preset) {
    setState(() {
      _selectedPreset = preset;
      if (_controller.text.trim().isEmpty ||
          _presets.contains(_controller.text.trim())) {
        _controller.text = preset;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Insets.screen,
        0,
        Insets.screen,
        Insets.lg + bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: palette.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Icon(Icons.cancel_rounded, color: palette.danger),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reject expense',
                      style: context.text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tell them what to fix so they can resubmit.',
                      style: context.text.bodySmall?.copyWith(
                        color: palette.neutral,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.xl),
          Text(
            'QUICK REASONS',
            style: context.text.labelSmall?.copyWith(color: palette.neutral),
          ),
          const SizedBox(height: Insets.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in _presets)
                ChoiceChip(
                  label: Text(preset),
                  selected: _selectedPreset == preset ||
                      _controller.text.trim() == preset,
                  onSelected: (_) => _pickPreset(preset),
                ),
            ],
          ),
          const SizedBox(height: Insets.lg),
          Text(
            'MESSAGE',
            style: context.text.labelSmall?.copyWith(color: palette.neutral),
          ),
          const SizedBox(height: Insets.sm),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Add a clear note for the submitter…',
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.md),
              ),
            ),
          ),
          const SizedBox(height: Insets.xl),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                flex: 2,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: palette.danger,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _canSubmit
                      ? () => Navigator.pop(context, _reason)
                      : null,
                  child: const Text('Reject expense'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RejectionNote extends StatelessWidget {
  const _RejectionNote({required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return HuddleCard(
      color: palette.dangerContainer,
      borderColor: palette.danger.withValues(alpha: 0.25),
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cancel_rounded, size: 17, color: palette.danger),
              const SizedBox(width: Insets.sm),
              Text(
                'Why this was rejected',
                style: context.text.titleSmall?.copyWith(color: palette.onDanger),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          Text(
            expense.decisionNote,
            style: context.text.bodyMedium?.copyWith(
              color: palette.onDanger,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicyFlag extends StatelessWidget {
  const _PolicyFlag({required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final overage = expense.overageAmount;
    if (overage == null) return const SizedBox.shrink();

    return HuddleCard(
      color: palette.warningContainer,
      borderColor: palette.warning.withValues(alpha: 0.3),
      elevated: false,
      padding: const EdgeInsets.all(Insets.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.flag_rounded, size: 16, color: palette.warning),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Text(
              'Over the ${Fmt.money(expense.category.limit!)} '
              '${expense.category.label.toLowerCase()} limit by ${Fmt.money(overage)}.',
              style: context.text.bodySmall?.copyWith(
                color: palette.onWarning,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, this.value, this.child});

  final String label;
  final String? value;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: [
        Text(
          label,
          style: context.text.bodyMedium?.copyWith(color: palette.neutral),
        ),
        const Spacer(),
        child ??
            Text(
              value ?? '',
              style: context.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
      ],
    );
  }
}
