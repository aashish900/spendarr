import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/profile.dart';
import '../theme.dart';
import 'field_card.dart';
import 'pill_selector.dart';

String _budgetModeLabel(BudgetMode m) => switch (m) {
      BudgetMode.constant => 'Every month is the same',
      BudgetMode.monthly => 'Ask me each month',
    };

/// One dialog for all three budget entry points: first-run setup, the
/// monthly re-prompt (mode already chosen, amount only), and editing from
/// Settings. `0` is a valid budget (blank ring) — there's no min-1
/// validation.
class BudgetPromptDialog extends ConsumerStatefulWidget {
  const BudgetPromptDialog({
    super.key,
    required this.canCancel,
    required this.showModeChoice,
    required this.title,
    this.initialCents,
    this.initialMode,
  });

  /// `false` for first-run setup and the monthly re-prompt — blocking,
  /// no way to dismiss without saving a value.
  final bool canCancel;

  /// `true` for first-run setup and Settings edits (user picks/changes the
  /// mode); `false` for the monthly re-prompt, where the mode is already
  /// fixed and only the amount needs re-entering.
  final bool showModeChoice;

  final String title;
  final int? initialCents;
  final BudgetMode? initialMode;

  @override
  ConsumerState<BudgetPromptDialog> createState() =>
      _BudgetPromptDialogState();
}

class _BudgetPromptDialogState extends ConsumerState<BudgetPromptDialog> {
  late final _amountController = TextEditingController(
    text: widget.initialCents == null
        ? ''
        : (widget.initialCents! / 100).toStringAsFixed(0),
  );
  late BudgetMode _mode = widget.initialMode ?? BudgetMode.constant;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _amountController.text.trim();
    final rupees = double.tryParse(raw);
    if (rupees == null || rupees < 0) {
      setState(() => _error = 'Enter a valid amount (0 or more)');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(profileProvider.notifier).saveBudget(
            cents: (rupees * 100).round(),
            mode: widget.showModeChoice ? _mode : null,
          );
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('MONTHLY BUDGET'),
        FieldCard(
          child: TextField(
            controller: _amountController,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: false),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              prefixText: '₹ ',
              prefixStyle: TextStyle(color: Colors.white),
              hintText: 'e.g. 20000',
              hintStyle: TextStyle(color: kTextMuted),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(_error!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12)),
          ),
        if (widget.showModeChoice) ...[
          const SizedBox(height: 20),
          const SectionLabel('REPEAT'),
          PillSelector<BudgetMode>(
            items: BudgetMode.values,
            selected: _mode,
            labelFor: _budgetModeLabel,
            onChanged: (m) => setState(() => _mode = m),
          ),
        ],
        const SizedBox(height: 24),
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
                : const Text('Save',
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.w600)),
          ),
        ),
        if (widget.canCancel) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: kTextSecondary)),
          ),
        ],
      ],
    );

    return PopScope(
      canPop: widget.canCancel,
      child: AlertDialog(
        backgroundColor: kSurfaceBlack,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: kCardBorder),
        ),
        title: Text(widget.title,
            style: const TextStyle(color: Colors.white, fontSize: 18)),
        content: SingleChildScrollView(child: content),
      ),
    );
  }
}

/// Shows [BudgetPromptDialog] with `barrierDismissible` matching
/// `canCancel` (a blocking dialog must not be dismissible by tapping the
/// barrier either).
Future<void> showBudgetPromptDialog(
  BuildContext context, {
  required bool canCancel,
  required bool showModeChoice,
  required String title,
  int? initialCents,
  BudgetMode? initialMode,
}) {
  return showDialog(
    context: context,
    barrierDismissible: canCancel,
    builder: (_) => BudgetPromptDialog(
      canCancel: canCancel,
      showModeChoice: showModeChoice,
      title: title,
      initialCents: initialCents,
      initialMode: initialMode,
    ),
  );
}
