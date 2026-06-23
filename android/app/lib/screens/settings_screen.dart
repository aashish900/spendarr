import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/api_error.dart';
import '../api/client.dart';
import '../providers/settings.dart';

/// Settings → Server: backend URL + bearer token + Save + Test connection.
/// (Sync-now / last-sync indicator deferred with B7.)
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _prefilled = false;
  bool _testing = false;

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  AppSettings _currentInput() => AppSettings(
        baseUrl: _urlController.text.trim(),
        token: _tokenController.text.trim(),
      );

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    await ref.read(settingsProvider.notifier).save(_currentInput());
    if (mounted) _snack('Settings saved');
  }

  Future<void> _testConnection() async {
    // Persist first so the dio client picks up the entered URL/token.
    await ref.read(settingsProvider.notifier).save(_currentInput());
    setState(() => _testing = true);
    try {
      await ref.read(apiClientProvider).health();
      if (mounted) _snack('Connection OK');
    } on ApiError catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Prefill once when settings finish loading from secure storage.
    final settings = ref.watch(settingsProvider);
    if (!_prefilled && settings.hasValue) {
      final s = settings.value!;
      _urlController.text = s.baseUrl ?? '';
      _tokenController.text = s.token ?? '';
      _prefilled = true;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Backend URL',
              hintText: 'http://<tailscale-host>:8000',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tokenController,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Bearer token',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _testing ? null : _testConnection,
            child: _testing
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Test connection'),
          ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.ios_share),
            title: const Text('Export CSV'),
            onTap: () => context.push('/export'),
          ),
        ],
      ),
    );
  }
}
