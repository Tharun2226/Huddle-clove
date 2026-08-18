/// Timezone-safe helpers for API date payloads.
///
/// Instant timestamps (task due, meeting start) go through UTC ISO.
/// Calendar dates (expense day) keep the user's selected year/month/day.
abstract final class DateCodec {
  /// Parse an API instant and convert to the device's local timezone.
  static DateTime? parseInstant(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.parse(raw).toLocal();
  }

  /// Encode a local instant for the API.
  static String encodeInstant(DateTime local) =>
      local.toUtc().toIso8601String();

  /// Parse a calendar date without shifting the day across timezones.
  ///
  /// Accepts `YYYY-MM-DD` or a full ISO string; always returns a local
  /// `DateTime` at midnight on that calendar day.
  static DateTime? parseCalendarDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final trimmed = raw.trim();
    // Bare date from API / OCR — take Y-M-D as the user's calendar day.
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) {
      final parts = trimmed.split('-');
      return DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    }
    // Full instant: use local calendar day so prior midnight→UTC bugs recover.
    final dt = DateTime.parse(trimmed).toLocal();
    return DateTime(dt.year, dt.month, dt.day);
  }

  /// Encode a local calendar date as `YYYY-MM-DD` (no timezone shift).
  static String encodeCalendarDate(DateTime local) {
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
