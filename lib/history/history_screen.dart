import 'package:flutter/material.dart';

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

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<ScanEntry>, HistorySummary)>(
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
              'This is a scan log, not a payment confirmation. Tap a row to mark it paid.',
              style: TextStyle(fontSize: 11, color: AppTokens.mist.withValues(alpha: 0.9)),
            ),
          ),
        ],
      );

  Widget _row(ScanEntry e) {
    final time = DateTime.fromMillisecondsSinceEpoch(e.timeMillis);
    final color = categoryColor(e.category);
    return InkWell(
      onTap: () async {
        await widget.repo.markPaid(e.timeMillis, !e.paid);
        _reload();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
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
                  Text(
                    '${_fmtTime(time)} · ${e.category.name}',
                    style: const TextStyle(color: AppTokens.mist, fontSize: 11),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  e.amount != null ? '₹${e.amount!.toStringAsFixed(0)}' : 'enter amt',
                  style: const TextStyle(
                      fontFamily: AppTokens.mono, color: AppTokens.cloud, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  e.paid ? 'paid ✓' : 'tap to confirm',
                  style: TextStyle(
                      fontSize: 10,
                      color: e.paid ? AppTokens.lime : AppTokens.mist),
                ),
              ],
            ),
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
