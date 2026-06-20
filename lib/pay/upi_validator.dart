import 'upi.dart';

/// How safe a scanned UPI request looks.
enum UpiSafety { ok, caution, blocked }

class UpiVerdict {
  final UpiSafety safety;
  final String? reason; // user-facing message; null when ok
  final UpiRequest? request; // null only when unparseable

  const UpiVerdict(this.safety, this.reason, this.request);
}

// Structural VPA check: `local@handle`. Permissive on length (we're rejecting
// non-VPA garbage like URLs or strings with no '@', not enforcing bank rules).
final _vpa = RegExp(r'^[a-zA-Z0-9.\-_]{1,256}@[a-zA-Z][a-zA-Z0-9.\-_]{0,64}$');

bool _tooManyDecimals(String s) {
  final dot = s.indexOf('.');
  return dot >= 0 && s.length - dot - 1 > 2;
}

/// The single security gate. Everything that pays runs through this first.
UpiVerdict validateUpi(String raw) {
  final req = parseUpi(raw);
  if (req == null) {
    return const UpiVerdict(UpiSafety.blocked, 'Not a UPI payment QR.', null);
  }
  if (req.action != 'pay') {
    return UpiVerdict(
      UpiSafety.blocked,
      'This QR is a request to collect money FROM you, not a payment.',
      req,
    );
  }
  if (!_vpa.hasMatch(req.payeeVpa)) {
    return UpiVerdict(UpiSafety.blocked, 'Payee UPI address looks invalid.', req);
  }
  final am = Uri.parse(raw.trim()).queryParameters['am'];
  if (am != null && am.isNotEmpty) {
    final v = double.tryParse(am);
    if (v == null || v <= 0 || _tooManyDecimals(am)) {
      return UpiVerdict(UpiSafety.blocked, 'The amount in this QR is invalid.', req);
    }
  }
  if (req.currency != 'INR') {
    return UpiVerdict(
      UpiSafety.caution,
      'Currency is ${req.currency}, not INR — pay only if you expect that.',
      req,
    );
  }
  return UpiVerdict(UpiSafety.ok, null, req);
}

/// Used at confirm time (the entered/decoded amount may differ from the QR).
bool isLargeAmount(double amount, {double threshold = 5000}) =>
    amount >= threshold;
