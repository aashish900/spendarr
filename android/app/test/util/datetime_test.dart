import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/util/datetime.dart';

void main() {
  group('occurredAtMs', () {
    test('combines a calendar date with an hour/minute into UTC epoch ms', () {
      final date = DateTime(2026, 6, 17);
      final ms = occurredAtMs(date, hour: 14, minute: 5);
      final backToLocal = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();

      expect(backToLocal.year, 2026);
      expect(backToLocal.month, 6);
      expect(backToLocal.day, 17);
      expect(backToLocal.hour, 14);
      expect(backToLocal.minute, 5);
    });

    test('ignores any time-of-day already present on the date argument', () {
      final date = DateTime(2026, 6, 17, 23, 59); // stray time component
      final ms = occurredAtMs(date, hour: 9, minute: 0);
      final backToLocal = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();

      expect(backToLocal.hour, 9);
      expect(backToLocal.minute, 0);
    });
  });

  group('formatTimeOfDay', () {
    test('formats as zero-padded 24-hour HH:mm', () {
      final ms = occurredAtMs(DateTime(2026, 6, 17), hour: 9, minute: 5);
      expect(formatTimeOfDay(ms), '09:05');
    });

    test('midnight and near-midnight format correctly', () {
      final midnight = occurredAtMs(DateTime(2026, 6, 17), hour: 0, minute: 0);
      final almostMidnight =
          occurredAtMs(DateTime(2026, 6, 17), hour: 23, minute: 59);
      expect(formatTimeOfDay(midnight), '00:00');
      expect(formatTimeOfDay(almostMidnight), '23:59');
    });
  });

  group('greetingFor', () {
    test('boundaries: 05:00 morning, 12:00 afternoon, 17:00 evening, else night', () {
      expect(greetingFor(DateTime(2026, 7, 14, 4, 59)), 'Good Night');
      expect(greetingFor(DateTime(2026, 7, 14, 5, 0)), 'Good Morning');
      expect(greetingFor(DateTime(2026, 7, 14, 11, 59)), 'Good Morning');
      expect(greetingFor(DateTime(2026, 7, 14, 12, 0)), 'Good Afternoon');
      expect(greetingFor(DateTime(2026, 7, 14, 16, 59)), 'Good Afternoon');
      expect(greetingFor(DateTime(2026, 7, 14, 17, 0)), 'Good Evening');
      expect(greetingFor(DateTime(2026, 7, 14, 20, 59)), 'Good Evening');
      expect(greetingFor(DateTime(2026, 7, 14, 21, 0)), 'Good Night');
      expect(greetingFor(DateTime(2026, 7, 14, 23, 59)), 'Good Night');
    });
  });

  group('monthLabel', () {
    test('formats year and month as a readable label', () {
      expect(monthLabel(2026, 7), 'July 2026');
      expect(monthLabel(2026, 1), 'January 2026');
      expect(monthLabel(2026, 12), 'December 2026');
    });
  });

  group('formatDayMonthYear', () {
    test('formats as "d Mon yyyy"', () {
      expect(formatDayMonthYear(DateTime(2026, 7, 16)), '16 Jul 2026');
      expect(formatDayMonthYear(DateTime(2026, 1, 1)), '1 Jan 2026');
      expect(formatDayMonthYear(DateTime(2026, 12, 31)), '31 Dec 2026');
    });
  });

  group('weekdayName', () {
    test('formats the full weekday name', () {
      expect(weekdayName(DateTime(2026, 7, 16)), 'Thursday'); // known Thu
      expect(weekdayName(DateTime(2026, 7, 13)), 'Monday');
      expect(weekdayName(DateTime(2026, 7, 19)), 'Sunday');
    });
  });

  group('formatTime12h', () {
    test('formats hour/minute as 12-hour with AM/PM', () {
      expect(formatTime12h(10, 47), '10:47 AM');
      expect(formatTime12h(14, 30), '2:30 PM');
      expect(formatTime12h(0, 0), '12:00 AM'); // midnight
      expect(formatTime12h(12, 0), '12:00 PM'); // noon
      expect(formatTime12h(23, 59), '11:59 PM');
      expect(formatTime12h(1, 5), '1:05 AM');
    });
  });
}
