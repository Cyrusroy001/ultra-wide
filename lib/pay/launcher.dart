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
