import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../db/database.dart';
import '../db/tables.dart';
import '../providers/categories.dart';
import '../providers/transactions.dart';
import '../util/money.dart';

/// Add a transaction. Writes to local drift + outbox (no sync). [initialCategoryId]
/// pre-selects a category when arriving via a Today quick-add chip.
class AddTxnScreen extends ConsumerStatefulWidget {
  const AddTxnScreen({super.key, this.initialCategoryId});

  final String? initialCategoryId;

  @override
  ConsumerState<AddTxnScreen> createState() => _AddTxnScreenState();
}

class _AddTxnScreenState extends ConsumerState<AddTxnScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  TransactionKind _kind = TransactionKind.expense;
  DateTime _date = DateTime.now();
  String? _categoryId;
  bool _categoryDefaulted = false;
  String? _amountError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.initialCategoryId;
    if (_categoryId != null) _categoryDefaulted = true;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// occurredAt for the chosen calendar date, pinned to local noon to keep it
  /// unambiguously inside that day regardless of timezone.
  int _occurredAtMs() =>
      DateTime(_date.year, _date.month, _date.day, 12).toUtc().millisecondsSinceEpoch;

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final cents = parseAmountToCents(_amountController.text);
    setState(() => _amountError = cents == null ? 'Enter a valid amount' : null);
    if (cents == null) return;
    if (_categoryId == null) {
      _snack('Pick a category');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(transactionWriterProvider).add(
            amountCents: cents,
            kind: _kind,
            categoryId: _categoryId!,
            occurredAtMs: _occurredAtMs(),
            note: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
          );
      if (mounted) {
        _snack('Saved');
        context.pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(activeCategoriesProvider);
    final categories = categoriesAsync.value ?? const <Category>[];

    // Default to the first category once loaded (unless one was passed in).
    if (!_categoryDefaulted && categories.isNotEmpty) {
      _categoryId = categories.first.id;
      _categoryDefaulted = true;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Add transaction')),
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
            segments: const [
              ButtonSegment(
                  value: TransactionKind.expense, label: Text('Expense')),
              ButtonSegment(
                  value: TransactionKind.income, label: Text('Income')),
              ButtonSegment(
                  value: TransactionKind.investment,
                  label: Text('Investment')),
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
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: Text(
                '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
            onPressed: _pickDate,
          ),
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
