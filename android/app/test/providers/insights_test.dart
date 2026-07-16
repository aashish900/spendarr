import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/tables.dart';
import 'package:spendarr/providers/insights.dart';
import 'package:spendarr/util/cron.dart';

RecurringRule _rule({
  required String id,
  required String categoryId,
  required String cron,
  bool active = true,
  String? note,
}) {
  return RecurringRule(
    id: id,
    categoryId: categoryId,
    amount: 64900,
    kind: TransactionKind.expense,
    note: note,
    cron: cron,
    active: active,
    nextRunAt: null,
    createdAt: 0,
    updatedAt: 0,
    deletedAt: null,
  );
}

Category _category(String id, String name) => Category(
      id: id,
      name: name,
      emoji: '🔁',
      kind: TransactionKind.expense,
      createdAt: 0,
      updatedAt: 0,
      deletedAt: null,
    );

void main() {
  group('upcomingRenewal', () {
    final now = DateTime(2026, 7, 14, 10, 0); // Tuesday

    test('picks the soonest active rule firing within 7 days', () {
      final rules = [
        _rule(
            id: 'r-monthly',
            categoryId: 'c1',
            cron: cronForPreset(RecurrencePreset.monthly)), // next: Aug 1 — >7d
        _rule(
            id: 'r-daily',
            categoryId: 'c2',
            cron: cronForPreset(RecurrencePreset.daily)), // next: tomorrow
      ];
      final categories = {'c1': _category('c1', 'Rent'), 'c2': _category('c2', 'Coffee')};

      final fact = upcomingRenewal(rules, categories, now);
      expect(fact, isNotNull);
      expect(fact!.label, 'Coffee');
    });

    test('skips paused rules', () {
      final rules = [
        _rule(
            id: 'r1',
            categoryId: 'c1',
            cron: cronForPreset(RecurrencePreset.daily),
            active: false),
      ];
      expect(upcomingRenewal(rules, {'c1': _category('c1', 'Netflix')}, now),
          isNull);
    });

    test('skips a genuine custom cron (unparseable next-fire)', () {
      final rules = [
        _rule(id: 'r1', categoryId: 'c1', cron: '15 9 5 * 3'),
      ];
      expect(upcomingRenewal(rules, {'c1': _category('c1', 'Gym')}, now),
          isNull);
    });

    test('null when no rules are within the 7-day horizon', () {
      final rules = [
        _rule(
            id: 'r1',
            categoryId: 'c1',
            cron: cronForPreset(RecurrencePreset.monthly)),
      ];
      // now = the 14th; monthly next-fire is the 1st of next month — >7 days out.
      expect(upcomingRenewal(rules, {'c1': _category('c1', 'Rent')}, now),
          isNull);
    });

    test('label falls back to category name when note is empty', () {
      final rules = [
        _rule(
            id: 'r1',
            categoryId: 'c1',
            cron: cronForPreset(RecurrencePreset.daily),
            note: ''),
      ];
      final fact =
          upcomingRenewal(rules, {'c1': _category('c1', 'Tea')}, now);
      expect(fact!.label, 'Tea');
    });

    test('label prefers the rule note when set', () {
      final rules = [
        _rule(
            id: 'r1',
            categoryId: 'c1',
            cron: cronForPreset(RecurrencePreset.daily),
            note: 'Netflix'),
      ];
      final fact =
          upcomingRenewal(rules, {'c1': _category('c1', 'Entertainment')}, now);
      expect(fact!.label, 'Netflix');
    });
  });

  group('renewalPhrase', () {
    final now = DateTime(2026, 7, 14, 10, 0);

    test('today', () {
      final fireMs =
          DateTime(2026, 7, 14, 18, 0).toUtc().millisecondsSinceEpoch;
      expect(renewalPhrase(fireMs, now), 'today');
    });

    test('tomorrow', () {
      final fireMs =
          DateTime(2026, 7, 15, 0, 0).toUtc().millisecondsSinceEpoch;
      expect(renewalPhrase(fireMs, now), 'tomorrow');
    });

    test('in N days', () {
      final fireMs =
          DateTime(2026, 7, 18, 0, 0).toUtc().millisecondsSinceEpoch;
      expect(renewalPhrase(fireMs, now), 'in 4 days');
    });
  });
}
