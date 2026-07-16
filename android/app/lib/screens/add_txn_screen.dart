import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../db/database.dart';
import '../db/database_provider.dart';
import '../db/tables.dart';
import '../providers/categories.dart';
import '../providers/recurring.dart';
import '../providers/transactions.dart';
import '../theme.dart';
import '../util/cron.dart';
import '../util/datetime.dart' as dt;
import '../util/money.dart';
import '../widgets/category_form.dart';
import '../widgets/category_icon_bubble.dart';
import '../widgets/field_card.dart';
import '../widgets/gilded.dart';
import '../widgets/kind_pill_selector.dart';

const _newCategoryValue = '__new__';

/// Add or edit a transaction. Writes to local drift + outbox (no sync).
/// [initialCategoryId] pre-selects a category (create mode only), aligning
/// [_kind] to that category's own kind. [initialKind] pre-selects a kind
/// directly (e.g. from the Home FAB's Income/Expense/Investment sheet) —
/// ignored when [initialCategoryId] is also set (category alignment wins)
/// or in edit mode (the loaded transaction's kind wins). [editTransactionId],
/// when set, loads and edits an existing transaction instead of creating one.
class AddTxnScreen extends ConsumerStatefulWidget {
  const AddTxnScreen({
    super.key,
    this.initialCategoryId,
    this.editTransactionId,
    this.initialKind,
  });

  final String? initialCategoryId;
  final String? editTransactionId;
  final TransactionKind? initialKind;

  @override
  ConsumerState<AddTxnScreen> createState() => _AddTxnScreenState();
}

class _AddTxnScreenState extends ConsumerState<AddTxnScreen> {
  final _amountController = TextEditingController();
  final _amountFocus = FocusNode();
  final _noteController = TextEditingController();
  final _customCronController = TextEditingController();

  TransactionKind _kind = TransactionKind.expense;
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();
  String? _categoryId;
  bool _categoryDefaulted = false;
  // True once we've looked up widget.initialCategoryId's own kind and
  // aligned _kind to it (a quick-add chip for an Income category should open
  // with Income pre-selected, not the Expense default).
  bool _kindAlignedToInitialCategory = false;
  String? _amountError;
  bool _saving = false;

  // Edit mode: whether the existing transaction (and any linked recurring
  // rule) has finished loading. Always true when creating a new transaction.
  bool _existingLoaded = true;
  // The recurring rule this transaction was already linked to when editing
  // started, if any — distinguishes "keep this rule in sync" from "create a
  // brand-new rule" when the recurring toggle is on at save time.
  String? _existingRecurringRuleId;

  bool _makeRecurring = false;
  RecurrencePreset _recurrencePreset = RecurrencePreset.monthly;
  String? _cronError;

  bool get _isEditing => widget.editTransactionId != null;

  @override
  void initState() {
    super.initState();
    if (widget.initialKind != null && widget.initialCategoryId == null) {
      _kind = widget.initialKind!;
    }
    _categoryId = widget.initialCategoryId;
    if (_categoryId != null) _categoryDefaulted = true;
    if (_isEditing) {
      _existingLoaded = false;
      _loadExisting();
    }
  }

  Future<void> _loadExisting() async {
    final db = ref.read(appDatabaseProvider);
    final txn = await db.transactionsDao.transactionById(widget.editTransactionId!);
    if (txn == null) {
      if (mounted) setState(() => _existingLoaded = true);
      return;
    }

    RecurringRule? rule;
    final linkedRuleId = txn.recurringRuleId;
    if (linkedRuleId != null) {
      rule = await db.recurringDao.ruleById(linkedRuleId);
    }
    if (!mounted) return;

    final occurred =
        DateTime.fromMillisecondsSinceEpoch(txn.occurredAt, isUtc: true)
            .toLocal();
    setState(() {
      _amountController.text = formatCents(txn.amount);
      _kind = txn.kind;
      _categoryId = txn.categoryId;
      _categoryDefaulted = true;
      _kindAlignedToInitialCategory = true; // no quick-add alignment in edit mode
      _date = DateTime(occurred.year, occurred.month, occurred.day);
      _time = TimeOfDay(hour: occurred.hour, minute: occurred.minute);
      _noteController.text = txn.note ?? '';
      _existingRecurringRuleId = linkedRuleId;
      if (rule != null) {
        _makeRecurring = true;
        _recurrencePreset = presetForCron(rule.cron);
        if (_recurrencePreset == RecurrencePreset.custom) {
          _customCronController.text = rule.cron;
        }
      }
      _existingLoaded = true;
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _amountFocus.dispose();
    _noteController.dispose();
    _customCronController.dispose();
    super.dispose();
  }

  /// occurredAt for the chosen calendar date + clock time.
  int _occurredAtMs() =>
      dt.occurredAtMs(_date, hour: _time.hour, minute: _time.minute);

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createCategory() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        // Scrollable: CategoryForm's fields + the keyboard (once a text
        // field is focused) can together exceed the sheet's height —
        // without this, the Save button could end up unreachable.
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: CategoryForm(
            initialKind: _kind,
            onSaved: (id, kind) {
              Navigator.of(sheetContext).pop();
              setState(() {
                _categoryId = id;
                _categoryDefaulted = true;
                _kind = kind;
              });
            },
          ),
        ),
      ),
    );
  }

  Future<void> _pickCategory(List<Category> categories) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: kSurfaceBlack,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          // Caps the sheet at 70% of the screen so a long category list
          // scrolls within it instead of overflowing off-screen and hiding
          // "New category" below the fold.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final c in categories)
                ListTile(
                  leading: CategoryIconBubble(c.emoji, size: 32),
                  title: Text(c.name),
                  onTap: () => Navigator.of(sheetContext).pop(c.id),
                ),
              ListTile(
                leading: Gilded(child: const Icon(Icons.add, color: Colors.white)),
                title: const Text('＋ New category'),
                onTap: () => Navigator.of(sheetContext).pop(_newCategoryValue),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    if (picked == _newCategoryValue) {
      await _createCategory();
      return;
    }
    setState(() => _categoryId = picked);
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

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _pickRecurrencePreset() async {
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
    if (picked != null) setState(() => _recurrencePreset = picked);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text(
            'This removes it from your totals and history. A linked '
            'recurring rule (if any) is not deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(transactionWriterProvider)
          .delete(widget.editTransactionId!);
      if (mounted) {
        _snack('Deleted');
        context.pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final cents = parseAmountToCents(_amountController.text);
    setState(() => _amountError = cents == null ? 'Enter a valid amount' : null);
    if (cents == null) return;
    if (_categoryId == null) {
      _snack('Pick a category');
      return;
    }

    String? cron;
    if (_makeRecurring) {
      cron = cronForPreset(_recurrencePreset, custom: _customCronController.text);
      setState(() => _cronError = isValidCron(cron!) ? null : 'Enter a valid 5-field cron');
      if (!isValidCron(cron)) return;
    }

    setState(() => _saving = true);
    try {
      final note =
          _noteController.text.trim().isEmpty ? null : _noteController.text.trim();

      String? recurringRuleId;
      if (_makeRecurring) {
        if (_existingRecurringRuleId != null) {
          // Keep the already-linked rule in sync with this transaction.
          await ref.read(recurringWriterProvider).update(
                id: _existingRecurringRuleId!,
                categoryId: _categoryId!,
                amountCents: cents,
                kind: _kind,
                cron: cron!,
                note: note,
              );
          recurringRuleId = _existingRecurringRuleId;
        } else {
          recurringRuleId = await ref.read(recurringWriterProvider).add(
                categoryId: _categoryId!,
                amountCents: cents,
                kind: _kind,
                cron: cron!,
                note: note,
                nextRunAtMs: nextRunAtMs(_recurrencePreset),
              );
        }
      }
      // else: recurringRuleId stays null — unlinks if it was previously linked.

      if (_isEditing) {
        await ref.read(transactionWriterProvider).update(
              id: widget.editTransactionId!,
              amountCents: cents,
              kind: _kind,
              categoryId: _categoryId!,
              occurredAtMs: _occurredAtMs(),
              note: note,
              recurringRuleId: recurringRuleId,
            );
      } else {
        await ref.read(transactionWriterProvider).add(
              amountCents: cents,
              kind: _kind,
              categoryId: _categoryId!,
              occurredAtMs: _occurredAtMs(),
              note: note,
              recurringRuleId: recurringRuleId,
            );
      }
      if (mounted) {
        _snack('Saved');
        context.pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
    if (!_existingLoaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Transaction'), centerTitle: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final categoriesAsync = ref.watch(activeCategoriesProvider);
    final allCategories = categoriesAsync.value ?? const <Category>[];

    // A quick-add chip passes a specific category's id; align _kind to that
    // category's own kind (once) so e.g. tapping an Income category chip
    // opens with Income pre-selected, not the Expense default.
    if (!_kindAlignedToInitialCategory &&
        widget.initialCategoryId != null &&
        allCategories.isNotEmpty) {
      for (final c in allCategories) {
        if (c.id == widget.initialCategoryId) {
          _kind = c.kind;
          break;
        }
      }
      _kindAlignedToInitialCategory = true;
    }

    // The picker only offers categories matching the selected kind — mixing
    // e.g. expense categories into an Income entry was the reported bug.
    final categories = allCategories.where((c) => c.kind == _kind).toList();

    // Default to the first matching category once loaded (unless one was
    // passed in and is still valid for the current kind).
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
        title: Text(_isEditing ? 'Edit Transaction' : 'Add Transaction'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: Gilded(child: const Icon(Icons.delete_outline, color: Colors.white)),
              tooltip: 'Delete',
              onPressed: _saving ? null : _confirmDelete,
            ),
        ],
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
              // The picker is filtered by kind — the previous selection may
              // no longer be valid, so let build() re-default it.
              _categoryId = null;
              _categoryDefaulted = false;
            }),
          ),
          const SizedBox(height: 20),
          const SectionLabel('CATEGORY'),
          FieldCard(
            onTap: () => _pickCategory(categories),
            child: Row(
              children: [
                Gilded(child: const Icon(Icons.grid_view_rounded, color: Colors.white)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    selectedCategory == null
                        ? 'Create or select category'
                        : selectedCategory.name,
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
          const SectionLabel('DATE & TIME'),
          Row(
            children: [
              Expanded(
                child: FieldCard(
                  onTap: _pickDate,
                  child: Row(
                    children: [
                      Gilded(
                          child: const Icon(Icons.calendar_today,
                              color: Colors.white, size: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(dt.formatDayMonthYear(_date),
                                style: const TextStyle(color: Colors.white)),
                            Text(dt.weekdayName(_date),
                                style:
                                    const TextStyle(color: kTextSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FieldCard(
                  onTap: _pickTime,
                  child: Row(
                    children: [
                      Gilded(
                          child: const Icon(Icons.access_time,
                              color: Colors.white, size: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(dt.formatTime12h(_time.hour, _time.minute),
                                style: const TextStyle(color: Colors.white)),
                            const Text('Edit time',
                                style: TextStyle(color: kTextSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
          const SizedBox(height: 20),
          const SectionLabel('MAKE THIS RECURRING'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (_makeRecurring)
                Expanded(
                  child: FieldCard(
                    onTap: _pickRecurrencePreset,
                    child: Row(
                      children: [
                        Gilded(
                            child: const Icon(Icons.autorenew,
                                color: Colors.white, size: 20)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(presetLabel(_recurrencePreset),
                                  style: const TextStyle(color: Colors.white)),
                              Text(_presetSubtitle(_recurrencePreset),
                                  style: const TextStyle(
                                      color: kTextSecondary, fontSize: 12)),
                            ],
                          ),
                        ),
                        Gilded(
                            child: const Icon(Icons.chevron_right, color: Colors.white)),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: Text('Repeat this transaction automatically',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: kTextSecondary)),
                ),
              const SizedBox(width: 12),
              Switch(
                value: _makeRecurring,
                activeThumbColor: kGold,
                onChanged: (v) => setState(() => _makeRecurring = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'This transaction will repeat automatically based on the frequency you choose.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: kTextSecondary),
          ),
          if (_makeRecurring && _recurrencePreset == RecurrencePreset.custom) ...[
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
                        Text(_isEditing ? 'Save Changes' : 'Save',
                            style: const TextStyle(
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

