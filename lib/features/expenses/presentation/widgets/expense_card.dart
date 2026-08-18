import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/utils/formatters.dart';
import '../../../../shared/widgets/huddle_card.dart';
import '../../../../shared/widgets/pill.dart';
import '../../domain/expense.dart';
import 'expense_visuals.dart';

/// Expense row used on the Expenses list, Today, and the approval queue.
class ExpenseCard extends ConsumerWidget {
  const ExpenseCard({
    super.key,
    required this.expense,
    this.onTap,
    this.showSubmitter = false,
  });

  final Expense expense;
  final VoidCallback? onTap;

  /// Managers need to know whose expense it is; members already know.
  final bool showSubmitter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final directory = ref.watch(teamById);
    final submitter = directory.resolve(expense.submitterId);
    final categoryColor = expense.category.color(palette);

    return HuddleCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Insets.md),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            alignment: Alignment.center,
            child: Icon(expense.category.icon, size: 21, color: categoryColor),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        expense.merchant,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                    Text(
                      Fmt.money(expense.amount),
                      style: context.text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        showSubmitter
                            ? '${submitter.firstName} · ${Fmt.friendlyDate(expense.date)}'
                            : '${expense.category.label} · ${Fmt.friendlyDate(expense.date)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelMedium?.copyWith(
                          color: palette.neutral,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                    if (expense.breachesPolicy && !expense.status.isSettled) ...[
                      Icon(
                        Icons.flag_rounded,
                        size: 13,
                        color: palette.danger,
                      ),
                      const SizedBox(width: 5),
                    ],
                    Pill(
                      label: expense.status.label,
                      color: expense.status.color(palette),
                      dense: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
