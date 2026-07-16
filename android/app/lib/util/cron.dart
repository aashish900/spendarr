// Recurrence helpers. v1 stores rules only — nothing executes them yet — so
// `nextRunAt` is a best-effort display hint, not a scheduler.

/// Recurrence presets offered by the Add recurring screen.
enum RecurrencePreset { daily, weekly, monthly, custom }

String presetLabel(RecurrencePreset p) => switch (p) {
      RecurrencePreset.daily => 'Daily',
      RecurrencePreset.weekly => 'Weekly',
      RecurrencePreset.monthly => 'Monthly',
      RecurrencePreset.custom => 'Custom',
    };

/// Reverse lookup: which preset (if any) produces exactly [cron]. Falls back
/// to [RecurrencePreset.custom] for anything that doesn't match a known
/// preset's fixed string — used to prefill the picker from a stored rule.
RecurrencePreset presetForCron(String cron) {
  for (final p in [
    RecurrencePreset.daily,
    RecurrencePreset.weekly,
    RecurrencePreset.monthly,
  ]) {
    if (cronForPreset(p) == cron) return p;
  }
  return RecurrencePreset.custom;
}

/// The 5-field cron string for a preset. For [RecurrencePreset.custom] the
/// user-entered [custom] string is returned verbatim (trimmed).
String cronForPreset(RecurrencePreset preset, {String custom = ''}) {
  switch (preset) {
    case RecurrencePreset.daily:
      return '0 0 * * *'; // 00:00 every day
    case RecurrencePreset.weekly:
      return '0 0 * * 1'; // 00:00 every Monday
    case RecurrencePreset.monthly:
      return '0 0 1 * *'; // 00:00 on the 1st
    case RecurrencePreset.custom:
      return custom.trim();
  }
}

/// Minimal validity check: exactly five non-empty whitespace-separated fields.
bool isValidCron(String cron) {
  final parts = cron.trim().split(RegExp(r'\s+'));
  return parts.length == 5 && parts.every((p) => p.isNotEmpty);
}

/// Best-effort next run instant (UTC epoch ms) for a preset, relative to
/// [from] (defaults to now). Null for custom (no parser in v1).
int? nextRunAtMs(RecurrencePreset preset, {DateTime? from}) {
  final now = from ?? DateTime.now();
  final tomorrow =
      DateTime(now.year, now.month, now.day).add(const Duration(days: 1));

  switch (preset) {
    case RecurrencePreset.daily:
      return tomorrow.toUtc().millisecondsSinceEpoch;
    case RecurrencePreset.weekly:
      var d = tomorrow;
      while (d.weekday != DateTime.monday) {
        d = d.add(const Duration(days: 1));
      }
      return d.toUtc().millisecondsSinceEpoch;
    case RecurrencePreset.monthly:
      final firstNextMonth = now.month == 12
          ? DateTime(now.year + 1, 1, 1)
          : DateTime(now.year, now.month + 1, 1);
      return firstNextMonth.toUtc().millisecondsSinceEpoch;
    case RecurrencePreset.custom:
      return null;
  }
}

/// Best-effort next fire instant (UTC epoch ms) for a raw [cron] string,
/// relative to [from] (defaults to now). Resolves through [presetForCron];
/// null for anything that isn't an exact preset match (no general cron
/// parser in v1).
int? nextFireMs(String cron, {DateTime? from}) =>
    nextRunAtMs(presetForCron(cron), from: from);

int _daysInMonth(int year, int month) {
  final firstNextMonth =
      month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
  return firstNextMonth.subtract(const Duration(days: 1)).day;
}

/// How many times a [cron] rule fires within the given [year]/[month].
/// Only handles the day-of-month-only and weekday-only shapes produced by
/// [cronForPreset] (daily/weekly/monthly) — anything else (a genuine custom
/// cron with both fields set, or unparseable fields) returns 0.
int occurrencesInMonth(String cron, int year, int month) {
  final parts = cron.trim().split(RegExp(r'\s+'));
  if (parts.length != 5) return 0;
  final dom = parts[2];
  final dow = parts[4];
  final daysInMonth = _daysInMonth(year, month);

  if (dom == '*' && dow == '*') {
    return daysInMonth; // daily
  }
  if (dom == '*' && dow != '*') {
    final weekday = int.tryParse(dow);
    if (weekday == null || weekday < 1 || weekday > 7) return 0;
    var count = 0;
    for (var day = 1; day <= daysInMonth; day++) {
      if (DateTime(year, month, day).weekday == weekday) count++;
    }
    return count; // weekly
  }
  if (dom != '*' && dow == '*') {
    final dayOfMonth = int.tryParse(dom);
    if (dayOfMonth == null) return 0;
    return dayOfMonth <= daysInMonth ? 1 : 0; // monthly
  }
  return 0; // both fields set — genuine custom cron, not supported
}
