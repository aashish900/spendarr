// Pure date/time helpers for combining a calendar date with a clock time and
// formatting the result. Kept dependency-free (no flutter/material) so the
// logic is unit-testable without a widget test harness.

/// UTC epoch ms for [date]'s calendar day at the given local [hour]:[minute].
/// Any time-of-day already present on [date] is ignored.
int occurredAtMs(DateTime date, {required int hour, required int minute}) {
  return DateTime(date.year, date.month, date.day, hour, minute)
      .toUtc()
      .millisecondsSinceEpoch;
}

/// Formats a UTC epoch-ms instant as the local zero-padded 24-hour `HH:mm`.
String formatTimeOfDay(int occurredAtMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(occurredAtMs, isUtc: true)
      .toLocal();
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

const _kMonthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Home greeting for the given local time. Boundaries: 05:00 Morning,
/// 12:00 Afternoon, 17:00 Evening, 21:00 Night.
String greetingFor(DateTime local) {
  final hour = local.hour;
  if (hour >= 5 && hour < 12) return 'Good Morning';
  if (hour >= 12 && hour < 17) return 'Good Afternoon';
  if (hour >= 17 && hour < 21) return 'Good Evening';
  return 'Good Night';
}

/// Formats a year/month pair as a readable label, e.g. `July 2026`.
String monthLabel(int year, int month) => '${_kMonthNames[month - 1]} $year';

const _kMonthNamesShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const _kWeekdayNamesFull = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

/// Formats a calendar date as `d Mon yyyy`, e.g. `16 Jul 2026`.
String formatDayMonthYear(DateTime date) =>
    '${date.day} ${_kMonthNamesShort[date.month - 1]} ${date.year}';

/// Full weekday name, e.g. `Thursday`.
String weekdayName(DateTime date) => _kWeekdayNamesFull[date.weekday - 1];

/// Formats an hour/minute pair as 12-hour clock time with AM/PM,
/// e.g. `10:47 AM`, `12:00 PM` (noon), `12:00 AM` (midnight).
String formatTime12h(int hour, int minute) {
  final period = hour < 12 ? 'AM' : 'PM';
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$hour12:${minute.toString().padLeft(2, '0')} $period';
}
