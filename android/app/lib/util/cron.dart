// Recurrence helpers. v1 stores rules only — nothing executes them yet — so
// `nextRunAt` is a best-effort display hint, not a scheduler.

/// Recurrence presets offered by the Add recurring screen.
enum RecurrencePreset { daily, weekly, monthly, custom }

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
