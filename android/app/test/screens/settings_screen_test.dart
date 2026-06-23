import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendarr/api/api_error.dart';
import 'package:spendarr/api/client.dart';
import 'package:spendarr/providers/settings.dart';
import 'package:spendarr/screens/settings_screen.dart';

class _FakeStore implements SettingsStore {
  _FakeStore([this.settings = const AppSettings()]);
  AppSettings settings;
  int saveCount = 0;

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings s) async {
    settings = s;
    saveCount++;
  }
}

class _FakeApi implements ApiClient {
  _FakeApi({this.error});
  final ApiError? error;

  @override
  Future<void> health() async {
    if (error != null) throw error!;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required SettingsStore store,
  required ApiClient api,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(api),
    ],
    child: const MaterialApp(home: SettingsScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Save persists entered values and shows snackbar',
      (tester) async {
    final store = _FakeStore();
    await _pump(tester, store: store, api: _FakeApi());

    await tester.enterText(find.byType(TextField).at(0), 'http://h:8000');
    await tester.enterText(find.byType(TextField).at(1), 'tok');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump(); // update() resolves
    await tester.pump(); // snackbar frame

    expect(store.saveCount, 1);
    expect(store.settings.baseUrl, 'http://h:8000');
    expect(store.settings.token, 'tok');
    expect(find.text('Settings saved'), findsOneWidget);
  });

  testWidgets('prefills fields from previously saved settings', (tester) async {
    final store = _FakeStore(
      const AppSettings(baseUrl: 'http://saved', token: 'savedtok'),
    );
    await _pump(tester, store: store, api: _FakeApi());

    expect(find.text('http://saved'), findsOneWidget);
  });

  testWidgets('Test connection success → "Connection OK" snackbar',
      (tester) async {
    await _pump(tester, store: _FakeStore(), api: _FakeApi());

    await tester.enterText(find.byType(TextField).at(0), 'http://h');
    await tester.enterText(find.byType(TextField).at(1), 't');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Test connection'));
    await tester.pump(); // update()
    await tester.pump(); // health() + snackbar

    expect(find.text('Connection OK'), findsOneWidget);
  });

  testWidgets('Test connection failure → ApiError message snackbar',
      (tester) async {
    final api = _FakeApi(
      error: const ApiError(
        kind: ApiErrorKind.unauthorized,
        message: 'auth failed — check bearer token in Settings',
      ),
    );
    await _pump(tester, store: _FakeStore(), api: api);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Test connection'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('auth failed — check bearer token in Settings'),
      findsOneWidget,
    );
  });
}
