import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database_provider.dart';
import '../db/tables.dart';
import '../providers/categories.dart';
import '../theme.dart';
import 'category_icon_bubble.dart';
import 'field_card.dart';
import 'kind_pill_selector.dart';

/// A handful of common emoji offered as one-tap shortcuts — not an
/// exhaustive or enforced set. The text field next to them accepts any
/// emoji typed via the system keyboard's emoji picker.
const _suggestedEmojis = [
  '💼', '💵', '🏦', '📈', '🍔', '☕', '🛒', '🏠', '🚗', '💡', '🎬', '🎁',
  '✈️', '📱', '💰', '👕', '🐶', '🏥',
];

/// Icon + name + kind + Save. Same card-based, gold "metallic" theme as
/// [AddTxnScreen]/[AddRecurringScreen]. Shared by the standalone Add/Edit
/// Category screen and the inline "New category" sheet on Add-transaction.
///
/// Creates a new category by default; passing [editCategoryId] switches to
/// edit mode — loads the existing category, prefills every field, and calls
/// [CategoryWriter.update] instead of [CategoryWriter.add] on save.
///
/// The icon picker accepts any emoji — either typed directly (the system
/// keyboard's emoji picker) or tapped from [_suggestedEmojis]'s shortcuts.
/// [CategoryIconBubble] gilds whatever's picked at display time, so there's
/// no curated map to keep in sync with the picker (see DECISIONLOG).
class CategoryForm extends ConsumerStatefulWidget {
  const CategoryForm({
    super.key,
    this.initialKind,
    this.editCategoryId,
    required this.onSaved,
  });

  final TransactionKind? initialKind;
  final String? editCategoryId;
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

  // Edit mode: whether the existing category has finished loading. Always
  // true when creating a new category.
  bool _existingLoaded = true;

  bool get _isEditing => widget.editCategoryId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _existingLoaded = false;
      _loadExisting();
    }
  }

  Future<void> _loadExisting() async {
    final db = ref.read(appDatabaseProvider);
    final category = await db.categoriesDao.categoryById(widget.editCategoryId!);
    if (!mounted) return;
    if (category == null) {
      setState(() => _existingLoaded = true);
      return;
    }
    setState(() {
      _nameController.text = category.name;
      _selectedEmoji = category.emoji;
      _emojiController.text = category.emoji;
      _kind = category.kind;
      _existingLoaded = true;
    });
  }

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
      final String id;
      if (_isEditing) {
        id = widget.editCategoryId!;
        await ref.read(categoryWriterProvider).update(
              id,
              name: name,
              emoji: _selectedEmoji,
              kind: _kind,
            );
      } else {
        id = await ref.read(categoryWriterProvider).add(
              name: name,
              emoji: _selectedEmoji,
              kind: _kind,
            );
      }
      if (mounted) widget.onSaved(id, _kind);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_existingLoaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('ICON'),
        FieldCard(
          child: Row(
            children: [
              CategoryIconBubble(_selectedEmoji, size: 48),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _emojiController,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Tap to enter any emoji',
                    hintStyle: TextStyle(color: kTextMuted, fontSize: 13),
                    border: InputBorder.none,
                    isDense: true,
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
        const SizedBox(height: 20),
        const SectionLabel('NAME'),
        FieldCard(
          child: TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'e.g. Groceries',
              hintStyle: TextStyle(color: kTextMuted),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
        if (_nameError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(_nameError!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12)),
          ),
        const SizedBox(height: 20),
        const SectionLabel('KIND'),
        KindPillSelector(
          selected: _kind,
          onChanged: (k) => setState(() => _kind = k),
        ),
        const SizedBox(height: 28),
        Container(
          decoration: BoxDecoration(
            gradient: kPremiumGoldGradient,
            borderRadius: BorderRadius.circular(999),
          ),
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.save_outlined, color: Colors.black),
                      const SizedBox(width: 8),
                      Text(_isEditing ? 'Update' : 'Save',
                          style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
