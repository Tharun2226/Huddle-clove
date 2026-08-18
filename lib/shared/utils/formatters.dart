import 'package:intl/intl.dart';

abstract final class Fmt {
  static final _currency = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  static final _currencyPrecise = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );
  static final _compact = NumberFormat.compactCurrency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 1,
  );

  static final _time = DateFormat('h:mm a');
  static final _dayMonth = DateFormat('d MMM');
  static final _dayMonthYear = DateFormat('d MMM yyyy');
  static final _weekdayLong = DateFormat('EEEE, d MMMM');
  static final _weekdayShort = DateFormat('EEE');

  /// Whole rupees — the default for lists and totals. Amounts here are always
  /// round enough that paise are noise.
  static String money(double amount) => _currency.format(amount);

  static String moneyPrecise(double amount) => _currencyPrecise.format(amount);

  /// Compact form for stat tiles where space is tight (₹1.2L, ₹8.5K).
  static String moneyCompact(double amount) =>
      amount.abs() >= 1000 ? _compact.format(amount) : _currency.format(amount);

  static String time(DateTime dt) => _time.format(dt).toLowerCase();

  static String dayMonth(DateTime dt) => _dayMonth.format(dt);

  static String dayMonthYear(DateTime dt) => _dayMonthYear.format(dt);

  static String weekdayLong(DateTime dt) => _weekdayLong.format(dt);

  static String weekdayShort(DateTime dt) => _weekdayShort.format(dt);

  static String timeRange(DateTime start, DateTime end) =>
      '${time(start)} – ${time(end)}';

  static String duration(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    final hours = d.inMinutes ~/ 60;
    final minutes = d.inMinutes % 60;
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }

  /// "Today" / "Tomorrow" / "Yesterday" where it reads better than a date.
  static String friendlyDate(DateTime dt) {
    final days = _daysBetween(DateTime.now(), dt);
    return switch (days) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ when days > 1 && days < 7 => weekdayShort(dt),
      _ when dt.year == DateTime.now().year => dayMonth(dt),
      _ => dayMonthYear(dt),
    };
  }

  /// Due-date label for task rows: leads with urgency, not the raw date.
  static String dueLabel(DateTime due) {
    final now = DateTime.now();
    final days = _daysBetween(now, due);
    if (days == 0) {
      return due.isBefore(now) ? 'Due today' : 'Due ${time(due)}';
    }
    if (days == 1) return 'Due tomorrow';
    if (days == -1) return 'Overdue by a day';
    if (days < -1) return 'Overdue by ${-days} days';
    if (days < 7) return 'Due ${weekdayShort(due)}';
    return 'Due ${dayMonth(due)}';
  }

  /// "just now" / "5m ago" / "3h ago" / "2d ago" for the activity feed.
  static String relative(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.isNegative) {
      final ahead = dt.difference(DateTime.now());
      if (ahead.inMinutes < 60) return 'in ${ahead.inMinutes}m';
      if (ahead.inHours < 24) return 'in ${ahead.inHours}h';
      return 'in ${ahead.inDays}d';
    }
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return dayMonth(dt);
  }

  /// Countdown used on the "next meeting" card.
  ///
  /// Pass [end] when available so finished meetings never read as "In progress".
  static String startsIn(DateTime start, {DateTime? end}) {
    final now = DateTime.now();
    if (end != null && !now.isBefore(end)) return 'Done';
    final diff = start.difference(now);
    if (diff.isNegative) {
      if (end == null || now.isBefore(end)) return 'In progress';
      return 'Done';
    }
    if (diff.inMinutes < 1) return 'Starting now';
    if (diff.inMinutes < 60) return 'in ${diff.inMinutes} min';
    if (diff.inHours < 24) {
      final mins = diff.inMinutes % 60;
      return mins == 0 ? 'in ${diff.inHours}h' : 'in ${diff.inHours}h ${mins}m';
    }
    return friendlyDate(start);
  }

  static String greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// Calendar-day difference, ignoring the time component so "tomorrow at 1am"
  /// is 1 day away rather than 0. Uses local calendar days (not UTC).
  static int _daysBetween(DateTime from, DateTime to) {
    final aLocal = from.toLocal();
    final bLocal = to.toLocal();
    final a = DateTime(aLocal.year, aLocal.month, aLocal.day);
    final b = DateTime(bLocal.year, bLocal.month, bLocal.day);
    return b.difference(a).inDays;
  }
}
