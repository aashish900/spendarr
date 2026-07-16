import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/tables.dart';
import '../providers/categories.dart';
import '../screens/categories_screen.dart' show kindLabel;
import '../theme.dart';
import 'category_icon_bubble.dart';
import 'field_card.dart';

/// A handful of common emoji offered as one-tap shortcuts — not an
/// exhaustive or enforced set. The text field next to them accepts any
/// emoji typed via the system keyboard's emoji picker.
const _suggestedEmojis = [
  '💼', '💵', '🏦', '📈', '🍔', '☕', '🛒', '🏠', '🚗', '💡', '🎬', '🎁',
  '✈️', '📱', '💰', '👕', '🐶', '🏥',
];

/// Icon + name + kind + Save. Writes a new category through
/// [categoryWriterProvider] and reports the new id via [onSaved]. Shared by
/// the standalone Add-category screen and the inline sheet on Add-transaction.
///
/// The icon picker accepts any emoji — either typed directly (the system
/// keyboard's emoji picker) or tapped from [_suggestedEmojis]'s shortcuts.
/// [CategoryIconBubble] gilds whatever's picked at display time, so there's
/// no curated map to keep in sync with the picker (see DECISIONLOG).
class CategoryForm extends ConsumerStatefulWidget {
  const CategoryForm({super.key, this.initialKind, required this.onSaved});

  final TransactionKind? initialKind;
  final void Function(String id, TransactionKind kind) onSaved;

  @override
  ConsumerState<CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends ConsumerState<CategoryForm> {
  final _nameController = TextEditingController();
  late final _emojiController =
      TextEditingController(text: _suggestedEmojis.first);
  String _selectedEmoji = _suggestedEmojis.first;
  late TransactionKind _kind = widget.initialKind ?? TransactionKind.expense;
  String? _nameError;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  void _pickEmoji(String e) {
    setState(() {
      _selectedEmoji = e;
      _emojiController.text = e;
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    setState(() => _nameError = name.isEmpty ? 'Enter a name' : null);
    if (name.isEmpty) return;

    setState(() => _saving = true);
    try {
      final id = await ref.read(categoryWriterProvider).add(
            name: name,
            emoji: _selectedEmoji,
            kind: _kind,
          );
      if (mounted) widget.onSaved(id, _kind);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('ICON'),
        Row(
          children: [
            CategoryIconBubble(_selectedEmoji, size: 56),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _emojiController,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24),
                decoration: const InputDecoration(
                  labelText: 'Tap to enter any emoji',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  final trimmed = v.trim();
                  if (trimmed.isEmpty) return;
                  setState(() => _selectedEmoji = trimmed);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in _suggestedEmojis)
              GestureDetector(
                onTap: () => _pickEmoji(e),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: e == _selectedEmoji
                          ? kGold
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: CategoryIconBubble(e, size: 40),
                ),
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
    );
  }
}
