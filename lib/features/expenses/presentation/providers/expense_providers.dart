import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/domain/app_user.dart';
import '../../../../core/auth/session_controller.dart';
import '../../../../core/di/providers.dart';
import '../../domain/expense.dart';

final expensesProvider = StreamProvider<List<Expense>>(
  (ref) => ref.watch(expenseRepositoryProvider).watchExpenses(),
);

/// API already scopes by role. Drafts stay private to the creator.
final visibleExpensesProvider = Provider<List<Expense>>((ref) {
  final expenses = ref.watch(expensesProvider).value ?? const [];
  final me = ref.watch(sessionControllerProvider);
  if (me == null) return const [];

  return expenses.where((e) {
    if (e.status == ExpenseStatus.draft) return e.submitterId == me.id;
    if (me.isAdmin || me.role == UserRole.manager) return true;
    return e.submitterId == me.id;
  }).toList();
});

final expenseByIdProvider = Provider.family<Expense?, String>((ref, id) {
  final expenses = ref.watch(visibleExpensesProvider);
  for (final expense in expenses) {
    if (expense.id == id) return expense;
  }
  return null;
});

/// Approval queue — submitted expenses the current manager/admin can decide,
/// including their own (admins and managers may self-approve).
final pendingApprovalsProvider = Provider<List<Expense>>((ref) {
  final me = ref.watch(sessionControllerProvider);
  if (me == null || !me.canApproveExpenses) return const [];
  final expenses = ref.watch(visibleExpensesProvider);
  final queue =
      expenses.where((e) => e.status.isPendingApproval).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return queue;
});

/// Expenses approved but not yet paid out — the guide's reimbursement tracking.
final awaitingReimbursementProvider = Provider<List<Expense>>((ref) {
  final expenses = ref.watch(visibleExpensesProvider)
      .where((e) => e.status == ExpenseStatus.approved)
      .toList();
  return expenses;
});

@immutable
class ExpenseTotals {
  const ExpenseTotals({
    required this.pending,
    required this.approved,
    required this.reimbursed,
    required this.thisMonth,
  });

  final double pending;
  final double approved;
  final double reimbursed;
  final double thisMonth;
}

final expenseTotalsProvider = Provider<ExpenseTotals>((ref) {
  final expenses = ref.watch(visibleExpensesProvider);
  final now = DateTime.now();
  var pending = 0.0, approved = 0.0, reimbursed = 0.0, thisMonth = 0.0;

  for (final expense in expenses) {
    switch (expense.status) {
      case ExpenseStatus.submitted:
        pending += expense.amount;
      case ExpenseStatus.approved:
        approved += expense.amount;
      case ExpenseStatus.reimbursed:
        reimbursed += expense.amount;
      case ExpenseStatus.draft:
      case ExpenseStatus.rejected:
        break;
    }
    if (expense.date.year == now.year &&
        expense.date.month == now.month &&
        expense.status != ExpenseStatus.rejected) {
      thisMonth += expense.amount;
    }
  }

  return ExpenseTotals(
    pending: pending,
    approved: approved,
    reimbursed: reimbursed,
    thisMonth: thisMonth,
  );
});

/// null means "all statuses".
class ExpenseFilterController extends Notifier<ExpenseStatus?> {
  @override
  ExpenseStatus? build() => null;

  void set(ExpenseStatus? status) => state = status;
}

final expenseFilterProvider =
    NotifierProvider<ExpenseFilterController, ExpenseStatus?>(
      ExpenseFilterController.new,
    );

final filteredExpensesProvider = Provider<List<Expense>>((ref) {
  final expenses = ref.watch(visibleExpensesProvider);
  final filter = ref.watch(expenseFilterProvider);
  if (filter == null) return expenses;
  return expenses.where((e) => e.status == filter).toList();
});
