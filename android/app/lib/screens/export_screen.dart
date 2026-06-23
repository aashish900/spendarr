import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/export.dart';

/// Export transactions to CSV and hand off via the OS share sheet. Date range
/// defaults to all time.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  DateTimeRange? _range;
  bool _exporting = false;

  /// (fromMs, toMs) for the selected range, or (null, null) for all time.
  (int?, int?) _msRange() {
    final range = _range;
    if (range == null) return (null, null);
    final start =
        DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day)
        .add(const Duration(days: 1));
    return (
      start.toUtc().millisecondsSinceEpoch,
      end.toUtc().millisecondsSinceEpoch,
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final dir = await ref.read(cacheDirProvider.future);
      final (fromMs, toMs) = _msRange();
      final file = await ref.read(exportServiceProvider).exportToCsv(
            cacheDir: dir,
            fromMs: fromMs,
            toMs: toMs,
          );
      await ref.read(fileSharerProvider).shareCsv(file.path);
      if (mounted) _snack('Exported CSV');
    } catch (e) {
      if (mounted) _snack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  String _rangeLabel() {
    final range = _range;
    if (range == null) return 'All time';
    String d(DateTime t) =>
        '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    return '${d(range.start)} → ${d(range.end)}';
  }

  @override
  Widget build(BuildContext context) {
    final (fromMs, toMs) = _msRange();
    final countAsync = ref.watch(exportRowCountProvider((fromMs, toMs)));

    return Scaffold(
      appBar: AppBar(title: const Text('Export CSV')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date range'),
            subtitle: Text(_rangeLabel()),
            trailing: Wrap(
              children: [
                if (_range != null)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'All time',
                    onPressed: () => setState(() => _range = null),
                  ),
                IconButton(
                  icon: const Icon(Icons.date_range),
                  tooltip: 'Pick range',
                  onPressed: _pickRange,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          countAsync.when(
            loading: () => const Text('Counting…'),
            error: (e, _) => Text('Error: $e'),
            data: (count) => Text('$count transaction(s) will be exported'),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.ios_share),
            label: _exporting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Export CSV'),
            onPressed: _exporting ? null : _export,
          ),
        ],
      ),
    );
  }
}
