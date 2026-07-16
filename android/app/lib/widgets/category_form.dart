import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/tables.dart';
import '../providers/categories.dart';
import '../screens/categories_screen.dart' show kindLabel;
import '../theme.dart';
import '../util/category_icon.dart';
import 'category_icon_bubble.dart';
import 'field_card.dart';

/// Icon + name + kind + Save. Writes a new category through
/// [categoryWriterProvider] and reports the new id via [onSaved]. Shared by
/// the standalone Add-category screen and the inline sheet on Add-transaction.
///
/// The icon picker only offers [categoryIconChoices] — every choice has a
/// real entry in the emoji→icon map, so what the user taps here is exactly
/// what renders everywhere else (no silent fallback-icon remapping).
class CategoryForm extends ConsumerStatefulWidget {
  const CategoryForm({super.key, this.initialKind, required this.onSaved});

  final TransactionKind? initialKind;
  final void Function(String id, TransactionKind kind) onSaved;

  @override
  ConsumerState<CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends ConsumerState<CategoryForm> {
  final _nameController = TextEditingController();
  String _selectedEmoji = categoryIconChoices.first;
  late TransactionKind _kind = widget.initialKind ?? TransactionKind.expense;
  String? _nameError;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in categoryIconChoices)
              GestureDetector(
                onTap: () => setState(() => _selectedEmoji = e),
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
