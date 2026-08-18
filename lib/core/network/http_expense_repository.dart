import 'dart:async';

import '../../../features/expenses/data/expense_repository.dart';
import '../../../features/expenses/domain/expense.dart';
import 'api_expense_repository.dart';

class HttpExpenseRepository implements ExpenseRepository {
  HttpExpenseRepository(this._api);

  final ApiExpenseRepository _api;

  final _controller = StreamController<List<Expense>>.broadcast();
  List<Expense> _expenses = const [];

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(List.unmodifiable(_expenses));
    }
  }

  void _replace(Expense expense) {
    final i = _expenses.indexWhere((e) => e.id == expense.id);
    if (i < 0) {
      _expenses = [expense, ..._expenses];
    } else {
      _expenses = [..._expenses]..[i] = expense;
    }
    _emit();
  }

  Future<void> _refresh() async {
    try {
      final list = await _api.fetchExpenses();
      _expenses = [...list]..sort((a, b) => b.date.compareTo(a.date));
      _emit();
    } catch (e, st) {
      if (_expenses.isEmpty && !_controller.isClosed) {
        _controller.addError(e, st);
      }
    }
  }

  @override
  Stream<List<Expense>> watchExpenses() {
    unawaited(_refresh());
    return Stream.multi((listener) {
      listener.add(_expenses);
      final sub = _controller.stream.listen(
        listener.add,
        onError: listener.addError,
        onDone: listener.close,
      );
      listener.onCancel = sub.cancel;
    });
  }

  @override
  Future<Expense> create(ExpenseDraft draft) async {
    final expense = await _api.create(draft);
    _replace(expense);
    return expense;
  }

  @override
  Future<Expense> update(Expense expense, {bool submitNow = false}) async {
    final updated = await _api.update(expense, submitNow: submitNow);
    _replace(updated);
    return updated;
  }

  @override
  Future<Expense> submit(String expenseId) async {
    final updated = await _api.submit(expenseId);
    _replace(updated);
    return updated;
  }

  @override
  Future<Expense> approve(String expenseId, {required String managerId}) async {
    final updated = await _api.approve(expenseId);
    _replace(updated);
    return updated;
  }

  @override
  Future<Expense> reject(
    String expenseId, {
    required String managerId,
    required String reason,
  }) async {
    final updated = await _api.reject(expenseId, reason: reason);
    _replace(updated);
    return updated;
  }

  @override
  Future<Expense> markReimbursed(
    String expenseId, {
    required String managerId,
  }) async {
    final updated = await _api.reimburse(expenseId);
    _replace(updated);
    return updated;
  }

  @override
  Future<void> delete(String expenseId) async {
    final previous = _expenses;
    _expenses = _expenses.where((e) => e.id != expenseId).toList(growable: false);
    _emit();
    try {
      await _api.delete(expenseId);
    } catch (e) {
      _expenses = previous;
      _emit();
      rethrow;
    }
  }

  @override
  Future<ScannedReceipt> scanReceipt(String imagePath) {
    return _api.scanReceipt(imagePath);
  }

  void dispose() {
    _controller.close();
  }
}
