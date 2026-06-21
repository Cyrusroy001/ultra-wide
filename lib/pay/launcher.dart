import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';

import 'upi.dart';

class LaunchResult {
  final bool launched;
  final String? error;
  const LaunchResult(this.launched, this.error);
}

/// Fires the UPI intent. Does NOT gate on resolveActivity (Android 11+
/// package-visibility makes it unreliable) — it just launches and catches the
/// failure. [package] pins a chosen default app; null shows the system chooser.
Future<LaunchResult> launchUpiUri(String uri, {String? package}) async {
  try {
    final intent = AndroidIntent(
      action: 'action_view',
      data: uri,
      package: package,
      flags: const <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
    );
    await intent.launch();
    return const LaunchResult(true, null);
  } catch (_) {
    return const LaunchResult(false, 'No UPI app could open this payment.');
  }
}

/// Produces the `upi://pay` string handed to the UPI app. CRITICAL: it starts
/// from the EXACT scanned QR (`base.raw`) so the merchant signature (`sign`),
/// `mode`, `orgid` and every other parameter survive byte-for-byte — a real UPI
/// app transmits the whole QR. Rebuilding from parsed fields drops `sign`, which
/// makes the payee bank reject a verified merchant as "not accepting payments".
///
/// [amount] null → pass the scanned QR through unchanged (fixed-amount / signed
/// merchant QR stays byte-identical). [amount] set → open-amount QR: keep every
/// original param, override `am` with the confirmed amount, ensure `cu` exists.
String buildUpiUri(UpiRequest base, {double? amount}) {
  final raw = base.raw;
  if (amount == null) return raw;

  final qi = raw.indexOf('?');
  final head = qi >= 0 ? raw.substring(0, qi) : raw; // e.g. 'upi://pay'
  final kept = <String>[];
  var hasCu = false;
  if (qi >= 0) {
    for (final pair in raw.substring(qi + 1).split('&')) {
      if (pair.isEmpty) continue;
      final key = pair.split('=').first.toLowerCase();
      if (key == 'am') continue; // overridden below
      if (key == 'cu') hasCu = true;
      kept.add(pair); // preserve original encoding (incl. base64 `sign`)
    }
  }
  kept.add('am=${amount.toStringAsFixed(2)}');
  if (!hasCu) kept.add('cu=INR');
  return '$head?${kept.join('&')}';
}
