import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../db/database.dart';
import '../db/tables.dart';
import '../providers/categories.dart';
import '../providers/recurring.dart';
import '../theme.dart';
import '../util/cron.dart';
import '../util/money.dart';
import '../widgets/category_icon_bubble.dart';
import '../widgets/field_card.dart';
import '../widgets/gilded.dart';
import '../widgets/kind_pill_selector.dart';

/// Add a recurring rule. Writes to drift + outbox. Same card-based, gold
/// "metallic" theme as [AddTxnScreen] — recurring rules are conceptually a
/// template for future transactions, so the entry form should feel the same.
class AddRecurringScreen extends ConsumerStatefulWidget {
  const AddRecurringScreen({super.key});

  @override
  ConsumerState<AddRecurringScreen> createState() =>
      _AddRecurringScreenState();
}

class _AddRecurringScreenState extends ConsumerState<AddRecurringScreen> {
  final _amountController = TextEditingController();
  final _amountFocus = FocusNode();
  final _noteController = TextEditingController();
  final _customCronController = TextEditingController();

  TransactionKind _kind = TransactionKind.expense;
  RecurrencePreset _preset = RecurrencePreset.monthly;
  String? _categoryId;
  bool _categoryDefaulted = false;
  String? _amountError;
  String? _cronError;
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    _amountFocus.dispose();
    _noteController.dispose();
    _customCronController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final cents = parseAmountToCents(_amountController.text);
    final cron =
        cronForPreset(_preset, custom: _customCronController.text);
    setState(() {
      _amountError = cents == null ? 'Enter a valid amount' : null;
      _cronError = isValidCron(cron) ? null : 'Enter a valid 5-field cron';
    });
    if (cents == null || !isValidCron(cron)) return;
    if (_categoryId == null) {
      _snack('Pick a category');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(recurringWriterProvider).add(
            categoryId: _categoryId!,
            amountCents: cents,
            kind: _kind,
            cron: cron,
            note: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
            nextRunAtMs: nextRunAtMs(_preset),
          );
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickCategory(List<Category> categories) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: kSurfaceBlack,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in categories)
              ListTile(
                leading: CategoryIconBubble(c.emoji, size: 32),
                title: Text(c.name),
                onTap: () => Navigator.of(sheetContext).pop(c.id),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _categoryId = picked);
  }

  Future<void> _pickPreset() async {
    final picked = await showModalBottomSheet<RecurrencePreset>(
      context: context,
      backgroundColor: kSurfaceBlack,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in RecurrencePreset.values)
              ListTile(
                title: Text(presetLabel(p)),
                onTap: () => Navigator.of(sheetContext).pop(p),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _preset = picked);
  }

  String _presetSubtitle(RecurrencePreset p) => switch (p) {
        RecurrencePreset.daily => 'Every Day',
        RecurrencePreset.weekly => 'Every Week',
        RecurrencePreset.monthly => 'Every Month',
        RecurrencePreset.custom => _customCronController.text.isEmpty
            ? 'Custom schedule'
            : _customCronController.text,
      };

  @override
  Widget build(BuildContext context) {
    final allCategories =
        ref.watch(activeCategoriesProvider).value ?? const <Category>[];
    // Only categories matching the selected kind — same invariant as
    // AddTxnScreen (mixing kinds into a category picker is the bug it fixed).
    final categories = allCategories.where((c) => c.kind == _kind).toList();
    if (!_categoryDefaulted && categories.isNotEmpty) {
      _categoryId = categories.first.id;
      _categoryDefaulted = true;
    }

    Category? selectedCategory;
    for (final c in categories) {
      if (c.id == _categoryId) {
        selectedCategory = c;
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        leading: IconButton(
          icon: Gilded(child: const Icon(Icons.arrow_back, color: Colors.white)),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: const Text('Add recurring'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionLabel('AMOUNT'),
          FieldCard(
            child: Row(
              children: [
                Gilded(
                  child: Text('₹',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          )),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    focusNode: _amountFocus,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                    decoration: const InputDecoration(
                      hintText: '0.00',
                      hintStyle: TextStyle(color: kTextMuted),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.fromBorderSide(BorderSide(color: kGoldMuted)),
                  ),
                  child: IconButton(
                    onPressed: () => _amountFocus.requestFocus(),
                    icon: Gilded(child: const Icon(Icons.edit, size: 18, color: Colors.white)),
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          if (_amountError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(_amountError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
            ),
          const SizedBox(height: 20),
          KindPillSelector(
            selected: _kind,
            onChanged: (k) => setState(() {
              _kind = k;
              _categoryId = null;
              _categoryDefaulted = false;
            }),
          ),
          const SizedBox(height: 20),
          const SectionLabel('CATEGORY'),
          if (categories.isEmpty)
            Text('No categories yet — add one on the Categories screen.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: kTextSecondary))
          else
            FieldCard(
              onTap: () => _pickCategory(categories),
              child: Row(
                children: [
                  Gilded(child: const Icon(Icons.grid_view_rounded, color: Colors.white)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      selectedCategory?.name ?? 'Select category',
                      style: TextStyle(
                        color: selectedCategory == null ? kTextMuted : Colors.white,
                      ),
                    ),
                  ),
                  Gilded(child: const Icon(Icons.chevron_right, color: Colors.white)),
                ],
              ),
            ),
          const SizedBox(height: 20),
          const SectionLabel('REPEAT'),
          FieldCard(
            onTap: _pickPreset,
            child: Row(
              children: [
                Gilded(
                    child: const Icon(Icons.autorenew, color: Colors.white, size: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(presetLabel(_preset),
                          style: const TextStyle(color: Colors.white)),
                      Text(_presetSubtitle(_preset),
                          style: const TextStyle(color: kTextSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                Gilded(child: const Icon(Icons.chevron_right, color: Colors.white)),
              ],
            ),
          ),
          if (_preset == RecurrencePreset.custom) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _customCronController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Cron (5 fields)',
                hintText: '0 0 1 * *',
                errorText: _cronError,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const SectionLabel('NOTE (OPTIONAL)'),
          FieldCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Gilded(child: const Icon(Icons.notes, color: Colors.white, size: 20)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _noteController,
                    maxLength: 120,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      counterStyle: TextStyle(color: kTextMuted, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
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
                      children: const [
                        Icon(Icons.save_outlined, color: Colors.black),
                        SizedBox(width: 8),
                        Text('Save',
                            style: TextStyle(
                                color: Colors.black, fontWeight: FontWeight.w600)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
