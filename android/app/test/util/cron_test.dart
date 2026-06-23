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
}
