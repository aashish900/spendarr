import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/db/database.dart';
import 'package:spendarr/db/database_provider.dart';
import 'package:spendarr/db/seed_categories.dart';
import 'package:spendarr/db/tables.dart';
import 'package:spendarr/providers/categories.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWith((ref) => db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  int now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  test('fresh DB → inserts all defaults, enqueues outbox rows, sets flag',
      () async {
    await container.read(categorySeederProvider).seedDefaults();

    final cats = await db.categoriesDao.allCategories();
    expect(cats, hasLength(kDefaultCategories.length));
    for (final d in kDefaultCategories) {
      expect(cats.where((c) => c.name == d.name && c.kind == d.kind),
          hasLength(1));
    }

    final outbox = await db.outboxDao.queue();
    expect(outbox, hasLength(kDefaultCategories.length));
    expect(outbox.every((o) => o.targetTable == 'categories'), isTrue);

    expect(await db.syncMetaDao.getValue('default_categories_seeded'),
        'true');
  });

  test('second run is a no-op: no duplicates, no new outbox rows', () async {
    await container.read(categorySeederProvider).seedDefaults();
    final firstCount = (await db.categoriesDao.allCategories()).length;
    final firstOutbox = (await db.outboxDao.queue()).length;

    await container.read(categorySeederProvider).seedDefaults();

    expect(await db.categoriesDao.allCategories(), hasLength(firstCount));
    expect(await db.outboxDao.queue(), hasLength(firstOutbox));
  });

  test('pre-existing category with matching name (case-insensitive) is not duplicated',
      () async {
    await container.read(categoryWriterProvider).add(
          name: 'food',
          emoji: '🍕',
          kind: TransactionKind.expense,
        );

    await container.read(categorySeederProvider).seedDefaults();

    final cats = await db.categoriesDao.allCategories();
    final foodLike =
        cats.where((c) => c.name.toLowerCase() == 'food').toList();
    expect(foodLike, hasLength(1));
    expect(foodLike.single.emoji, '🍕'); // the user's hand-made row survives

    // Every other default still landed.
    expect(cats, hasLength(kDefaultCategories.length));
  });

  test('seeded rows carry UTC epoch-ms timestamps', () async {
    final before = now();
    await container.read(categorySeederProvider).seedDefaults();
    final after = now();

    final cats = await db.categoriesDao.allCategories();
    for (final c in cats) {
      expect(c.createdAt, inInclusiveRange(before, after));
      expect(c.updatedAt, inInclusiveRange(before, after));
      expect(c.deletedAt, isNull);
    }
  });
}
