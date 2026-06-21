import 'dart:convert';

import '../data/prefs.dart';
import '../pay/categories.dart';

/// One scan, captured from QR metadata at scan time. NOTE: this is a *scan log*,
/// not a payment ledger — the OS never tells us if a payment succeeded, so
/// [paid] is a manual user mark only.
class ScanEntry {
  final String vpa;
  final String? name;
  final double? amount;
  final PayCategory category;
  final int timeMillis;
  final String? note;
  final bool paid;

  const ScanEntry({
    required this.vpa,
    this.name,
    this.amount,
    required this.category,
    required this.timeMillis,
    this.note,
    this.paid = false,
  });

  ScanEntry copyWith({bool? paid}) => ScanEntry(
        vpa: vpa,
        name: name,
        amount: amount,
        category: category,
        timeMillis: timeMillis,
        note: note,
        paid: paid ?? this.paid,
      );

  Map<String, dynamic> toJson() => {
        'vpa': vpa,
        'name': name,
        'amount': amount,
        'category': category.name,
        'timeMillis': timeMillis,
        'note': note,
        'paid': paid,
      };

  factory ScanEntry.fromJson(Map<String, dynamic> j) => ScanEntry(
        vpa: j['vpa'],
        name: j['name'],
        amount: (j['amount'] as num?)?.toDouble(),
        category: PayCategory.values.byName(j['category']),
        timeMillis: j['timeMillis'],
        note: j['note'],
        paid: j['paid'] ?? false,
      );
}

/// Aggregates for the History summary strip. [knownAmountSum] is explicitly
/// partial — it sums only scans whose amount was known.
class HistorySummary {
  final int countThisMonth;
  final double knownAmountSum;
  final PayCategory? topCategory;

  const HistorySummary(this.countThisMonth, this.knownAmountSum, this.topCategory);
}

class HistoryRepo {
  final Prefs _p;
  HistoryRepo(this._p);

  Future<List<ScanEntry>> list() async {
    final s = _p.getString(PrefKeys.history);
    if (s == null) return [];
    return (jsonDecode(s) as List)
        .map((e) => ScanEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _save(List<ScanEntry> items) => _p.setString(
        PrefKeys.history,
        jsonEncode(items.map((e) => e.toJson()).toList()),
      );

  /// Prepends newest, caps the log at 200 entries.
  Future<void> add(ScanEntry e) async {
    final items = await list()..insert(0, e);
    if (items.length > 200) items.removeRange(200, items.length);
    await _save(items);
  }

  Future<void> markPaid(int timeMillis, bool paid) async {
    final items = (await list())
        .map((e) => e.timeMillis == timeMillis ? e.copyWith(paid: paid) : e)
        .toList();
    await _save(items);
  }

  /// Removes a single entry (e.g. a failed/abandoned scan the user clears).
  Future<void> delete(int timeMillis) async {
    final items = (await list())..removeWhere((e) => e.timeMillis == timeMillis);
    await _save(items);
  }

  /// Puts a previously-deleted entry back, keeping the log newest-first by time
  /// (so undo lands it at its original position, not the top).
  Future<void> restore(ScanEntry e) async {
    final items = await list();
    var i = items.indexWhere((x) => x.timeMillis < e.timeMillis);
    if (i < 0) i = items.length;
    items.insert(i, e);
    await _save(items);
  }

  Future<void> clear() => _p.remove(PrefKeys.history);

  Future<HistorySummary> summary() async {
    final items = await list();
    final now = DateTime.now();
    final month = items.where((e) {
      final d = DateTime.fromMillisecondsSinceEpoch(e.timeMillis);
      return d.year == now.year && d.month == now.month;
    }).toList();
    final sum = month
        .where((e) => e.amount != null)
        .fold<double>(0, (a, e) => a + e.amount!);
    final counts = <PayCategory, int>{};
    for (final e in month) {
      counts[e.category] = (counts[e.category] ?? 0) + 1;
    }
    PayCategory? top;
    counts.forEach((k, v) {
      if (top == null || v > counts[top]!) top = k;
    });
    return HistorySummary(month.length, sum, top);
  }
}
