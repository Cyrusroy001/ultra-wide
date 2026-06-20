import 'upi.dart';

/// Builds a `upi://pay` URI from a base request plus an (optionally overridden)
/// amount and note. Always emits `cu=INR`. The entered amount wins over the
/// QR's amount so the pay app opens pre-filled.
String buildUpiUri(UpiRequest base, {double? amount, String? note}) {
  final amt = amount ?? base.amount;
  final tn = note ?? base.note;
  final params = <String, String>{
    'pa': base.payeeVpa,
    'pn': ?base.payeeName,
    if (amt != null) 'am': amt.toStringAsFixed(2),
    'cu': 'INR',
    'tn': ?tn,
    'tr': ?base.txnRef,
    'mc': ?base.merchantCode,
  };
  final query = params.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');
  return 'upi://pay?$query';
}
