import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings.g.dart';

/// Immutable server-connection settings. The bearer token lives only here and
/// in secure storage — never in plain prefs or logs.
class AppSettings {
  const AppSettings({this.baseUrl, this.token});

  final String? baseUrl;
  final String? token;

  /// True when both a base URL and a token are present.
  bool get isConfigured =>
      (baseUrl?.isNotEmpty ?? false) && (token?.isNotEmpty ?? false);

  AppSettings copyWith({String? baseUrl, String? token}) => AppSettings(
        baseUrl: baseUrl ?? this.baseUrl,
        token: token ?? this.token,
      );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.baseUrl == baseUrl &&
      other.token == token;

  @override
  int get hashCode => Object.hash(baseUrl, token);
}

/// Persistence boundary for [AppSettings]. Abstracted so tests can swap in an
/// in-memory fake without touching platform channels.
abstract interface class SettingsStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

/// flutter_secure_storage-backed store (Android EncryptedSharedPreferences).
class SecureSettingsStore implements SettingsStore {
  SecureSettingsStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _kBaseUrl = 'backend_base_url';
  static const _kToken = 'bearer_token';

  @override
  Future<AppSettings> load() async {
    final baseUrl = await _storage.read(key: _kBaseUrl);
    final token = await _storage.read(key: _kToken);
    return AppSettings(baseUrl: baseUrl, token: token);
  }

  @override
  Future<void> save(AppSettings settings) async {
    await _storage.write(key: _kBaseUrl, value: settings.baseUrl);
    await _storage.write(key: _kToken, value: settings.token);
  }
}

@riverpod
SettingsStore settingsStore(Ref ref) =>
    SecureSettingsStore(const FlutterSecureStorage());

/// Reactive settings, loaded from secure storage on first read.
@riverpod
class Settings extends _$Settings {
  @override
  Future<AppSettings> build() => ref.watch(settingsStoreProvider).load();

  /// Persist new settings and update state optimistically. (Named `save` to
  /// avoid clashing with [AsyncNotifier.update].)
  Future<void> save(AppSettings settings) async {
    await ref.read(settingsStoreProvider).save(settings);
    state = AsyncData(settings);
  }
}
