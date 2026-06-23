import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../db/tables.dart';
import '../providers/categories.dart';
import 'categories_screen.dart' show kindLabel;

/// A small built-in set of starter emojis (no heavyweight emoji-picker dep).
const _quickEmojis = [
  '🍔', '🛒', '🏠', '🚗', '💡', '🎬', '💊', '🎁',
  '✈️', '📱', '💰', '📈', '☕', '👕', '🐶', '🏥',
];

/// Add a category: emoji + name + kind. Writes to drift + outbox.
class AddCategoryScreen extends ConsumerStatefulWidget {
  const AddCategoryScreen({super.key});

  @override
  ConsumerState<AddCategoryScreen> createState() => _AddCategoryScreenState();
}

class _AddCategoryScreenState extends ConsumerState<AddCategoryScreen> {
  final _nameController = TextEditingController();
  final _emojiController = TextEditingController(text: '🍔');
  TransactionKind _kind = TransactionKind.expense;
  String? _nameError;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final emoji = _emojiController.text.trim();
    setState(() => _nameError = name.isEmpty ? 'Enter a name' : null);
    if (name.isEmpty || emoji.isEmpty) return;

    setState(() => _saving = true);
    try {
      await ref.read(categoryWriterProvider).add(
            name: name,
            emoji: emoji,
            kind: _kind,
          );
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add category')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _emojiController,
            decoration: const InputDecoration(
              labelText: 'Emoji',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              for (final e in _quickEmojis)
                IconButton(
                  onPressed: () => setState(() => _emojiController.text = e),
                  icon: Text(e, style: const TextStyle(fontSize: 22)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Name',
              errorText: _nameError,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<TransactionKind>(
            segments: [
              for (final k in TransactionKind.values)
                ButtonSegment(value: k, label: Text(kindLabel(k))),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
