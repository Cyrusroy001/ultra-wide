/// A parsed `upi://` request. `action` is the URI host (e.g. `pay`, `collect`).
class UpiRequest {
  final String action;
  final String payeeVpa; // pa
  final String? payeeName; // pn
  final double? amount; // am, null = open amount
  final String currency; // cu
  final String? note; // tn
  final String? txnRef; // tr
  final String? merchantCode; // mc

  const UpiRequest({
    required this.action,
    required this.payeeVpa,
    this.payeeName,
    this.amount,
    this.currency = 'INR',
    this.note,
    this.txnRef,
    this.merchantCode,
  });
}

/// Parses a `upi:` URI. Returns null if it is not a UPI URI or has no payee.
/// Validation/safety classification is the job of `validateUpi`, not this.
UpiRequest? parseUpi(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.scheme.toLowerCase() != 'upi') return null;
  final q = uri.queryParameters;
  final pa = q['pa'];
  if (pa == null || pa.isEmpty) return null;
  final am = q['am'];
  final amount = (am != null && am.isNotEmpty) ? double.tryParse(am) : null;
  final host = uri.host.isNotEmpty ? uri.host : uri.path.replaceAll('/', '');
  return UpiRequest(
    action: host.toLowerCase(),
    payeeVpa: pa,
    payeeName: q['pn'],
    amount: amount,
    currency: (q['cu'] ?? 'INR').toUpperCase(),
    note: q['tn'],
    txnRef: q['tr'],
    merchantCode: q['mc'],
  );
}
