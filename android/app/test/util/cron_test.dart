import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/util/cron.dart';

void main() {
  group('cronForPreset', () {
    test('presets map to valid 5-field cron strings', () {
      expect(cronForPreset(RecurrencePreset.daily), '0 0 * * *');
      expect(cronForPreset(RecurrencePreset.weekly), '0 0 * * 1');
      expect(cronForPreset(RecurrencePreset.monthly), '0 0 1 * *');

      for (final p in [
        RecurrencePreset.daily,
        RecurrencePreset.weekly,
        RecurrencePreset.monthly,
      ]) {
        expect(isValidCron(cronForPreset(p)), isTrue, reason: '$p');
      }
    });

    test('custom returns the trimmed user input', () {
      expect(cronForPreset(RecurrencePreset.custom, custom: '  15 9 * * 3 '),
          '15 9 * * 3');
    });
  });

  group('isValidCron', () {
    test('accepts 5 fields, rejects others', () {
      expect(isValidCron('0 0 1 * *'), isTrue);
      expect(isValidCron('0 0 1 *'), isFalse); // 4 fields
      expect(isValidCron('0 0 1 * * *'), isFalse); // 6 fields
      expect(isValidCron(''), isFalse);
      expect(isValidCron('   '), isFalse);
    });
  });

  group('nextRunAtMs', () {
    final from = DateTime(2026, 6, 23, 15, 0); // Tue 23 Jun 2026

    test('daily → next local midnight', () {
      final ms = nextRunAtMs(RecurrencePreset.daily, from: from)!;
      final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
      expect(d, DateTime(2026, 6, 24));
    });

    test('weekly → next Monday', () {
      final ms = nextRunAtMs(RecurrencePreset.weekly, from: from)!;
      final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
      expect(d.weekday, DateTime.monday);
      expect(d, DateTime(2026, 6, 29));
    });

    test('monthly → 1st of next month', () {
      final ms = nextRunAtMs(RecurrencePreset.monthly, from: from)!;
      final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
      expect(d, DateTime(2026, 7, 1));
    });

    test('custom → null', () {
      expect(nextRunAtMs(RecurrencePreset.custom, from: from), isNull);
    });
  });

  group('occurrencesInMonth', () {
    test('daily fires every day of the month', () {
      // June 2026 has 30 days.
      expect(occurrencesInMonth(cronForPreset(RecurrencePreset.daily), 2026, 6),
          30);
      // February 2026 (non-leap) has 28 days.
      expect(occurrencesInMonth(cronForPreset(RecurrencePreset.daily), 2026, 2),
          28);
    });

    test('weekly fires once per matching weekday in the month', () {
      // July 2026 has 5 Mondays (6, 13, 20, 27) — actually 4; verify exactly.
      final cron = cronForPreset(RecurrencePreset.weekly); // Monday
      final mondays = List.generate(31, (i) => DateTime(2026, 7, i + 1))
          .where((d) => d.weekday == DateTime.monday)
          .length;
      expect(occurrencesInMonth(cron, 2026, 7), mondays);
    });

    test('monthly fires exactly once when the day-of-month exists', () {
      expect(
          occurrencesInMonth(cronForPreset(RecurrencePreset.monthly), 2026, 7),
          1);
    });

    test('a weekday-only custom cron counts like weekly', () {
      // dom=*, dow=3 (Wednesday) — same shape as the weekly preset.
      final wednesdays = List.generate(31, (i) => DateTime(2026, 7, i + 1))
          .where((d) => d.weekday == DateTime.wednesday)
          .length;
      expect(occurrencesInMonth('15 9 * * 3', 2026, 7), wednesdays);
    });

    test('custom cron with both day-of-month and weekday set → 0', () {
      expect(occurrencesInMonth('15 9 5 * 3', 2026, 7), 0);
    });
  });

  group('nextFireMs', () {
    final from = DateTime(2026, 6, 23, 15, 0);

    test('matches nextRunAtMs for each known preset', () {
      for (final p in [
        RecurrencePreset.daily,
        RecurrencePreset.weekly,
        RecurrencePreset.monthly,
      ]) {
        expect(nextFireMs(cronForPreset(p), from: from),
            nextRunAtMs(p, from: from));
      }
    });

    test('custom cron → null', () {
      expect(nextFireMs('15 9 * * 3', from: from), isNull);
    });
  });
}
