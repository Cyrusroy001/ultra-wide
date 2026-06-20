import 'package:flutter/material.dart';

import '../history/history_repo.dart';
import '../theme/tokens.dart';
import 'categories.dart';
import 'launcher.dart';
import 'upi_validator.dart';

typedef OnPay = Future<void> Function(String uri, ScanEntry entry);

/// The single review-before-pay surface. Shows the payee, the RAW VPA (so a
/// spoofed display name can't hide it), a safety shield, and either a fixed
/// amount or an in-app numpad. Pay only fires on explicit confirm.
class VerifySheet extends StatefulWidget {
  const VerifySheet({
    super.key,
    required this.verdict,
    required this.onPay,
    this.largeAmountThreshold = 5000,
  });

  final UpiVerdict verdict;
  final OnPay onPay;
  final double largeAmountThreshold;

  @override
  State<VerifySheet> createState() => _VerifySheetState();
}

class _VerifySheetState extends State<VerifySheet> {
  String _input = '';

  bool get _isFixed => widget.verdict.request?.amount != null;

  double get _amount =>
      _isFixed ? widget.verdict.request!.amount! : (double.tryParse(_input) ?? 0);

  @override
  Widget build(BuildContext context) {
    final v = widget.verdict;
    if (v.safety == UpiSafety.blocked) return _blocked(v.reason ?? 'Blocked.');

    final req = v.request!;
    final category = categorize(
      merchantCode: req.merchantCode,
      payeeName: req.payeeName,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: const BoxDecoration(
        color: AppTokens.slate,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTokens.radius)),
      ),
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _grip(),
          if (v.safety == UpiSafety.caution) _cautionBanner(v.reason ?? ''),
          Row(
            children: [
              _shield(v.safety),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req.payeeName ?? 'Unknown payee',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600, color: AppTokens.cloud),
                    ),
                    Text(
                      req.payeeVpa,
                      style: const TextStyle(
                          fontFamily: AppTokens.mono, fontSize: 13, color: AppTokens.mist),
                    ),
                  ],
                ),
              ),
              _categoryPill(category),
            ],
          ),
          const SizedBox(height: 18),
          _amountDisplay(),
          const SizedBox(height: 12),
          if (_isFixed) _fixedTag() else _numpad(),
          const SizedBox(height: 16),
          _payButton(req.payeeName),
        ],
        ),
      ),
    );
  }

  Widget _grip() => Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: AppTokens.slateSoft,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _blocked(String reason) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: const BoxDecoration(
          color: AppTokens.slate,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppTokens.radius)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _grip(),
            const Icon(Icons.block, color: AppTokens.alertRed, size: 40),
            const SizedBox(height: 12),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTokens.alertRed, fontSize: 15),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );

  Widget _cautionBanner(String reason) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTokens.amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTokens.amber.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber, color: AppTokens.amber, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(reason,
                  style: const TextStyle(color: AppTokens.amber, fontSize: 12)),
            ),
          ],
        ),
      );

  Widget _shield(UpiSafety s) {
    final (icon, color) = switch (s) {
      UpiSafety.ok => (Icons.verified_user, AppTokens.lime),
      UpiSafety.caution => (Icons.gpp_maybe, AppTokens.amber),
      UpiSafety.blocked => (Icons.gpp_bad, AppTokens.alertRed),
    };
    return Icon(icon, color: color, size: 28);
  }

  Widget _categoryPill(PayCategory c) {
    final color = categoryColor(c);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(c.name,
          style: TextStyle(color: color, fontSize: 11, fontFamily: AppTokens.mono)),
    );
  }

  Widget _amountDisplay() {
    final shown = _isFixed
        ? _amount.toStringAsFixed(2)
        : (_input.isEmpty ? '0' : _input);
    return Center(
      child: Text(
        '₹ $shown',
        style: const TextStyle(
            fontFamily: AppTokens.mono,
            fontSize: 40,
            fontWeight: FontWeight.w600,
            color: AppTokens.cloud),
      ),
    );
  }

  Widget _fixedTag() => const Center(
        child: Text('amount set by merchant',
            style: TextStyle(color: AppTokens.mist, fontSize: 12)),
      );

  Widget _numpad() {
    Widget key(String label, VoidCallback onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(label,
                    style: const TextStyle(
                        fontFamily: AppTokens.mono, fontSize: 22, color: AppTokens.cloud)),
              ),
            ),
          ),
        );

    void append(String d) => setState(() {
          if (d == '.' && _input.contains('.')) return;
          // cap to 2 decimals
          final dot = _input.indexOf('.');
          if (dot >= 0 && _input.length - dot - 1 >= 2) return;
          _input += d;
        });

    void backspace() => setState(() {
          if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
        });

    void addQuick(int n) => setState(() {
          final base = double.tryParse(_input) ?? 0;
          _input = (base + n).toStringAsFixed(0);
        });

    return Column(
      children: [
        Row(children: [
          _quick('+10', () => addQuick(10)),
          _quick('+50', () => addQuick(50)),
          _quick('+100', () => addQuick(100)),
        ]),
        const SizedBox(height: 8),
        Row(children: [key('1', () => append('1')), key('2', () => append('2')), key('3', () => append('3'))]),
        Row(children: [key('4', () => append('4')), key('5', () => append('5')), key('6', () => append('6'))]),
        Row(children: [key('7', () => append('7')), key('8', () => append('8')), key('9', () => append('9'))]),
        Row(children: [key('.', () => append('.')), key('0', () => append('0')), key('⌫', backspace)]),
      ],
    );
  }

  Widget _quick(String label, VoidCallback onTap) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: OutlinedButton(onPressed: onTap, child: Text(label)),
        ),
      );

  Widget _payButton(String? name) {
    final enabled = _amount > 0;
    return FilledButton(
      onPressed: enabled ? _confirmAndPay : null,
      style: FilledButton.styleFrom(
        backgroundColor: AppTokens.lime,
        foregroundColor: AppTokens.ink,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: Text('Pay ₹${_amount.toStringAsFixed(2)}${name != null ? " to $name" : ""}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Future<void> _confirmAndPay() async {
    final req = widget.verdict.request!;
    if (isLargeAmount(_amount, threshold: widget.largeAmountThreshold)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: AppTokens.slate,
          title: const Text('Large payment'),
          content: Text(
              'You are about to pay ₹${_amount.toStringAsFixed(2)} to ${req.payeeVpa}. Continue?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Pay')),
          ],
        ),
      );
      if (ok != true) return;
    }

    final uri = buildUpiUri(req, amount: _amount);
    final entry = ScanEntry(
      vpa: req.payeeVpa,
      name: req.payeeName,
      amount: _amount,
      category: categorize(merchantCode: req.merchantCode, payeeName: req.payeeName),
      timeMillis: DateTime.now().millisecondsSinceEpoch,
      note: req.note,
    );
    await widget.onPay(uri, entry);
  }
}
