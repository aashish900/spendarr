import '../db/database.dart';
import '../util/cron.dart';

/// A deterministic upcoming-renewal fact, derived from recurring rules —
/// no spending-pattern analysis (out of scope per CLAUDE.md §3).
class RenewalFact {
  const RenewalFact({required this.label, required this.fireMs});

  final String label;
  final int fireMs;
}

/// The soonest active recurring rule firing within 7 days of [now], or null
/// if none. Paused rules and rules with an unparseable ("genuine custom")
/// cron are skipped — [nextFireMs] returns null for those.
RenewalFact? upcomingRenewal(
  List<RecurringRule> rules,
  Map<String, Category> categoriesById,
  DateTime now,
) {
  final horizon = now.add(const Duration(days: 7));

  RecurringRule? best;
  int? bestFireMs;
  for (final r in rules) {
    if (!r.active) continue;
    final fireMs = nextFireMs(r.cron, from: now);
    if (fireMs == null) continue;
    final fireDate =
        DateTime.fromMillisecondsSinceEpoch(fireMs, isUtc: true).toLocal();
    if (fireDate.isBefore(now) || fireDate.isAfter(horizon)) continue;
    if (bestFireMs == null || fireMs < bestFireMs) {
      best = r;
      bestFireMs = fireMs;
    }
  }
  if (best == null || bestFireMs == null) return null;

  final note = best.note;
  final label = (note != null && note.isNotEmpty)
      ? note
      : categoriesById[best.categoryId]?.name ?? 'Recurring payment';
  return RenewalFact(label: label, fireMs: bestFireMs);
}

/// Formats [fireMs] relative to [now] as "today" / "tomorrow" / "in N days".
String renewalPhrase(int fireMs, DateTime now) {
  final fireDate =
      DateTime.fromMillisecondsSinceEpoch(fireMs, isUtc: true).toLocal();
  final fireDay = DateTime(fireDate.year, fireDate.month, fireDate.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = fireDay.difference(today).inDays;
  if (diff <= 0) return 'today';
  if (diff == 1) return 'tomorrow';
  return 'in $diff days';
}
