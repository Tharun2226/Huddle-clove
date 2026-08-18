import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/router/app_router.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/utils/formatters.dart';
import '../../../../shared/widgets/huddle_card.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../../domain/expense.dart';
import '../providers/expense_providers.dart';
import '../widgets/expense_card.dart';
import '../widgets/expense_visuals.dart';
import '../../../notifications/presentation/notification_bell.dart';

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expensesProvider);
    final expenses = ref.watch(filteredExpensesProvider);
    final totals = ref.watch(expenseTotalsProvider);
    final filter = ref.watch(expenseFilterProvider);
    final isManager = ref.watch(isManagerProvider);
    final loading = expensesAsync.isLoading && !expensesAsync.hasValue;
    final hasError = expensesAsync.hasError && !expensesAsync.hasValue;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: const [NotificationBell()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.newExpense),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Expense'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(expensesProvider);
          await Future<void>.delayed(const Duration(milliseconds: 600));
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.screen,
                  Insets.sm,
                  Insets.screen,
                  Insets.lg,
                ),
                child: _SummaryCard(totals: totals),
              ),
            ),
            SliverToBoxAdapter(child: _StatusFilter(selected: filter)),
            if (loading)
              const SliverPadding(
                padding: EdgeInsets.all(Insets.screen),
                sliver: SliverToBoxAdapter(child: SkeletonList(count: 4)),
              )
            else if (hasError)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Couldn’t load expenses',
                  message: 'Check your connection and try again.',
                  action: FilledButton(
                    onPressed: () => ref.invalidate(expensesProvider),
                    child: const Text('Retry'),
                  ),
                ),
              )
            else if (expenses.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyExpenses(filtered: filter != null, isManager: isManager),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.screen,
                  Insets.sm,
                  Insets.screen,
                  Insets.xxl * 3,
                ),
                sliver: SliverList.separated(
                  itemCount: expenses.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Insets.md),
                  itemBuilder: (context, index) {
                    final expense = expenses[index];
                    return ExpenseCard(
                      expense: expense,
                      showSubmitter: isManager,
                      onTap: () => context.push(Routes.expenseDetail(expense.id)),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Money summary. Leads with what is owed to you, because that is the question
/// people actually open this screen to answer.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.totals});

  final ExpenseTotals totals;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final outstanding = totals.pending + totals.approved;

    return HuddleCard(
      color: scheme.primary,
      borderColor: Colors.transparent,
      padding: const EdgeInsets.all(Insets.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OUTSTANDING',
            style: context.text.labelSmall?.copyWith(
              color: scheme.onPrimary.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: Insets.sm),
          Text(
            Fmt.money(outstanding),
            style: context.text.displaySmall?.copyWith(
              color: scheme.onPrimary,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: Insets.lg),
          Container(
            padding: const EdgeInsets.all(Insets.md),
            decoration: BoxDecoration(
              color: scheme.onPrimary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Row(
              children: [
                _Metric(
                  label: 'Pending',
                  value: Fmt.moneyCompact(totals.pending),
                ),
                _Divider(),
                _Metric(
                  label: 'Approved',
                  value: Fmt.moneyCompact(totals.approved),
                ),
                _Divider(),
                _Metric(
                  label: 'This month',
                  value: Fmt.moneyCompact(totals.thisMonth),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.md),
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 13,
                color: scheme.onPrimary.withValues(alpha: 0.65),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  totals.reimbursed > 0
                      ? '${Fmt.money(totals.reimbursed)} reimbursed so far'
                      : 'Submitted and approved, not yet paid out',
                  style: context.text.bodySmall?.copyWith(
                    color: scheme.onPrimary.withValues(alpha: 0.75),
                  ),
                ),
              ),
              Icon(
                Icons.trending_up_rounded,
                size: 15,
                color: scheme.onPrimary.withValues(alpha: 0.65),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.titleSmall?.copyWith(
              color: scheme.onPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.text.labelSmall?.copyWith(
              letterSpacing: 0.2,
              fontWeight: FontWeight.w500,
              color: scheme.onPrimary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 26,
      margin: const EdgeInsets.symmetric(horizontal: Insets.md),
      color: context.colors.onPrimary.withValues(alpha: 0.16),
    );
  }
}

class _StatusFilter extends ConsumerWidget {
  const _StatusFilter({required this.selected});

  final ExpenseStatus? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final scheme = context.colors;
    final controller = ref.read(expenseFilterProvider.notifier);

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Insets.screen),
        children: [
          _Chip(
            label: 'All',
            selected: selected == null,
            color: scheme.primary,
            onTap: () => controller.set(null),
          ),
          for (final status in ExpenseStatus.values) ...[
            const SizedBox(width: Insets.sm),
            _Chip(
              label: status.label,
              selected: selected == status,
              color: status.color(palette),
              onTap: () => controller.set(selected == status ? null : status),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.pill),
      child: AnimatedContainer(
        duration: Motion.fast,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : palette.neutralContainer,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.4) : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: context.text.labelMedium?.copyWith(
            color: selected ? color : palette.neutral,
          ),
        ),
      ),
    );
  }
}

class _EmptyExpenses extends ConsumerWidget {
  const _EmptyExpenses({required this.filtered, required this.isManager});

  final bool filtered;
  final bool isManager;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (filtered) {
      return EmptyState(
        icon: Icons.filter_alt_off_rounded,
        title: 'Nothing in this status',
        message: 'Try a different filter.',
        action: OutlinedButton.icon(
          onPressed: () => ref.read(expenseFilterProvider.notifier).set(null),
          icon: const Icon(Icons.clear_rounded, size: 18),
          label: const Text('Show all'),
        ),
      );
    }

    return EmptyState(
      icon: Icons.receipt_long_rounded,
      title: 'No expenses yet',
      message: isManager
          ? 'Submit your own expense with +, or wait for your team to submit theirs.'
          : 'Use + to scan a receipt — it takes about ten seconds.',
    );
  }
}
