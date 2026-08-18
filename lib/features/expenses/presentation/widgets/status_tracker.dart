import 'package:flutter/material.dart';

import '../../../../shared/theme/app_tokens.dart';
import '../../../../shared/utils/formatters.dart';
import '../../domain/expense.dart';
import 'expense_visuals.dart';

/// The Draft → Submitted → Approved → Reimbursed rail. Answers "where is my
/// money" without the user having to interpret a status word.
class StatusTracker extends StatelessWidget {
  const StatusTracker({super.key, required this.expense});

  final Expense expense;

  static const _steps = [
    ExpenseStatus.draft,
    ExpenseStatus.submitted,
    ExpenseStatus.approved,
    ExpenseStatus.reimbursed,
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final currentIndex = _steps.indexOf(expense.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < _steps.length; i++) ...[
              _Node(
                done: i < currentIndex,
                active: i == currentIndex,
                status: _steps[i],
              ),
              if (i != _steps.length - 1)
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: i < currentIndex ? 1 : 0),
                    duration: Motion.slow,
                    curve: Motion.emphasized,
                    builder: (context, value, _) => Container(
                      height: 2.5,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Radii.pill),
                        gradient: LinearGradient(
                          colors: [palette.success, palette.success, palette.neutralContainer],
                          stops: [0, value, value],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
        const SizedBox(height: Insets.md),
        Row(
          children: [
            for (var i = 0; i < _steps.length; i++)
              Expanded(
                child: Text(
                  _steps[i].label,
                  textAlign: i == 0
                      ? TextAlign.start
                      : i == _steps.length - 1
                      ? TextAlign.end
                      : TextAlign.center,
                  style: context.text.labelSmall?.copyWith(
                    letterSpacing: 0,
                    color: i <= currentIndex ? null : palette.neutral,
                    fontWeight: i == currentIndex ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Insets.lg),
        Container(
          padding: const EdgeInsets.all(Insets.md),
          decoration: BoxDecoration(
            color: expense.status.color(palette).withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Row(
            children: [
              Icon(
                expense.status.icon,
                size: 16,
                color: expense.status.color(palette),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Text(
                  _explainer(),
                  style: context.text.bodySmall?.copyWith(height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Prefer a concrete date over the generic status blurb when we have one.
  String _explainer() {
    if (expense.status == ExpenseStatus.reimbursed && expense.reimbursedAt != null) {
      return 'Paid out on ${Fmt.dayMonthYear(expense.reimbursedAt!)}.';
    }
    if (expense.status == ExpenseStatus.approved && expense.decidedAt != null) {
      return 'Approved ${Fmt.relative(expense.decidedAt!)}. Payment is being processed.';
    }
    return expense.status.explainer;
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.done, required this.active, required this.status});

  final bool done;
  final bool active;
  final ExpenseStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = done ? palette.success : status.color(palette);

    return AnimatedContainer(
      duration: Motion.normal,
      curve: Motion.emphasized,
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: done || active ? color.withValues(alpha: 0.16) : palette.neutralContainer,
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? color : Colors.transparent,
          width: 2,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        done ? Icons.check_rounded : status.icon,
        size: 13,
        color: done || active ? color : palette.neutral,
      ),
    );
  }
}
