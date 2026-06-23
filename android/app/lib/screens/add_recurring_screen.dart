import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../db/database.dart';
import '../db/tables.dart';
import '../providers/categories.dart';
import '../providers/recurring.dart';
import '../util/cron.dart';
import '../util/money.dart';
import 'categories_screen.dart' show kindLabel;

String _presetLabel(RecurrencePreset p) => switch (p) {
      RecurrencePreset.daily => 'Daily',
      RecurrencePreset.weekly => 'Weekly',
      RecurrencePreset.monthly => 'Monthly',
      RecurrencePreset.custom => 'Custom',
    };

/// Add a recurring rule. Writes to drift + outbox.
class AddRecurringScreen extends ConsumerStatefulWidget {
  const AddRecurringScreen({super.key});

  @override
  ConsumerState<AddRecurringScreen> createState() =>
      _AddRecurringScreenState();
}

class _AddRecurringScreenState extends ConsumerState<AddRecurringScreen> {
  final _amountController = TextEditingController();
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

  @override
  Widget build(BuildContext context) {
    final categories =
        ref.watch(activeCategoriesProvider).value ?? const <Category>[];
    if (!_categoryDefaulted && categories.isNotEmpty) {
      _categoryId = categories.first.id;
      _categoryDefaulted = true;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Add recurring')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount',
              hintText: '0.00',
              errorText: _amountError,
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
          const SizedBox(height: 16),
          if (categories.isEmpty)
            const Text('No categories yet — add one on the Categories screen.')
          else
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final c in categories)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text('${c.emoji}  ${c.name}'),
                  ),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<RecurrencePreset>(
            initialValue: _preset,
            decoration: const InputDecoration(
              labelText: 'Repeat',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final p in RecurrencePreset.values)
                DropdownMenuItem(value: p, child: Text(_presetLabel(p))),
            ],
            onChanged: (p) =>
                setState(() => _preset = p ?? RecurrencePreset.monthly),
          ),
          if (_preset == RecurrencePreset.custom) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _customCronController,
              decoration: InputDecoration(
                labelText: 'Cron (5 fields)',
                hintText: '0 0 1 * *',
                errorText: _cronError,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              border: OutlineInputBorder(),
            ),
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
