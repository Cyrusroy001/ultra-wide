import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'history_repo.dart';

/// The scan log — explicitly NOT a payment ledger (the OS never tells us if a
/// payment succeeded). "Paid" is a manual mark; spend totals are partial.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.repo});

  final HistoryRepo repo;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<(List<ScanEntry>, HistorySummary)> _future = _load();

  Future<(List<ScanEntry>, HistorySummary)> _load() async =>
      (await widget.repo.list(), await widget.repo.summary());

  // Block body on purpose: an arrow `=> _future = _load()` returns the assigned
  // Future, and setState() rejects a callback that returns a Future — which
  // silently aborted every refresh (the old "tap to confirm does nothing" bug).
  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _togglePaid(ScanEntry e) async {
    HapticFeedback.selectionClick();
    await widget.repo.markPaid(e.timeMillis, !e.paid);
    if (mounted) _reload();
  }

  Future<void> _delete(ScanEntry e) async {
    final messenger = ScaffoldMessenger.of(context);
    await widget.repo.delete(e.timeMillis);
    if (!mounted) return;
    _reload();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Scan deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await widget.repo.restore(e);
            if (mounted) _reload();
          },
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    // SafeArea: this screen is a bare Scaffold body (no AppBar), so without it
    // the summary strip slides under the status-bar clock.
    return SafeArea(
      child: FutureBuilder<(List<ScanEntry>, HistorySummary)>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppTokens.lime));
          }
          final (entries, summary) = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            color: AppTokens.lime,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _summaryStrip(summary),
                const SizedBox(height: 8),
                _honestyBanner(),
                const SizedBox(height: 8),
                if (entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text('No scans yet.',
                          style: TextStyle(color: AppTokens.mist)),
                    ),
                  )
                else
                  ...entries.map(_row),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _summaryStrip(HistorySummary s) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTokens.slate,
          borderRadius: BorderRadius.circular(AppTokens.radius),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _stat('${s.countThisMonth}', 'scans this month'),
            _stat('₹${s.knownAmountSum.toStringAsFixed(0)}', 'known total (partial)'),
            _stat(s.topCategory?.name ?? '—', 'top category'),
          ],
        ),
      );

  Widget _stat(String value, String label) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontFamily: AppTokens.mono,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.cloud)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: AppTokens.mist)),
        ],
      );

  Widget _honestyBanner() => Row(
        children: [
          const Icon(Icons.info_outline, size: 14, color: AppTokens.mist),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Scan log, not a payment confirmation — mark a scan paid or delete it.',
              style: TextStyle(fontSize: 11, color: AppTokens.mist.withValues(alpha: 0.9)),
            ),
          ),
        ],
      );

  Widget _row(ScanEntry e) {
    final time = DateTime.fromMillisecondsSinceEpoch(e.timeMillis);
    final color = categoryColor(e.category);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.name ?? e.vpa,
                    style: const TextStyle(color: AppTokens.cloud, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  '${_fmtTime(time)} · ${e.category.name}',
                  style: const TextStyle(color: AppTokens.mist, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                e.amount != null ? '₹${e.amount!.toStringAsFixed(0)}' : 'enter amt',
                style: const TextStyle(
                    fontFamily: AppTokens.mono, color: AppTokens.cloud, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _paidPill(e),
                  const SizedBox(width: 2),
                  IconButton(
                    onPressed: () => _delete(e),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
                    icon: const Icon(Icons.delete_outline, size: 18, color: AppTokens.mist),
                    tooltip: 'Delete scan',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Explicit, obviously-tappable paid toggle (the old whole-row tap gave almost
  /// no visual feedback, so it read as "not working").
  Widget _paidPill(ScanEntry e) {
    final paid = e.paid;
    return InkWell(
      onTap: () => _togglePaid(e),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: paid ? AppTokens.lime.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: paid ? AppTokens.lime : AppTokens.slateSoft),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(paid ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 13, color: paid ? AppTokens.lime : AppTokens.mist),
            const SizedBox(width: 4),
            Text(paid ? 'Paid' : 'Mark paid',
                style: TextStyle(
                    fontSize: 11, color: paid ? AppTokens.lime : AppTokens.mist)),
          ],
        ),
      ),
    );
  }

  String _fmtTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
  }
}
