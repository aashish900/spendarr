import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/providers/settings.dart';

/// In-memory [SettingsStore] — no platform channels.
class FakeSettingsStore implements SettingsStore {
  FakeSettingsStore([this._settings = const AppSettings()]);

  AppSettings _settings;
  int saveCount = 0;

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async {
    _settings = settings;
    saveCount++;
  }
}

void main() {
  ProviderContainer containerWith(FakeSettingsStore store) {
    final container = ProviderContainer(
      overrides: [settingsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('loads from store on first read', () async {
    final store = FakeSettingsStore(
      const AppSettings(baseUrl: 'http://host:8000', token: 'abc'),
    );
    final container = containerWith(store);

    final loaded = await container.read(settingsProvider.future);
    expect(loaded.baseUrl, 'http://host:8000');
    expect(loaded.isConfigured, isTrue);
  });

  test('unconfigured when empty', () async {
    final container = containerWith(FakeSettingsStore());
    final loaded = await container.read(settingsProvider.future);
    expect(loaded.isConfigured, isFalse);
  });

  test('update persists to store and refreshes state', () async {
    final store = FakeSettingsStore();
    final container = containerWith(store);
    await container.read(settingsProvider.future); // ensure built

    await container
        .read(settingsProvider.notifier)
        .save(const AppSettings(baseUrl: 'http://h', token: 't'));

    expect(store.saveCount, 1);
    final after = await container.read(settingsProvider.future);
    expect(after.baseUrl, 'http://h');
    expect(after.token, 't');
  });
}
