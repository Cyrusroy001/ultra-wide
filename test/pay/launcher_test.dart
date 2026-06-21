import 'package:flutter_test/flutter_test.dart';
import 'package:scanpay/pay/upi.dart';
import 'package:scanpay/pay/launcher.dart';

void main() {
  group('buildUpiUri preserves the scanned QR', () {
    test('passes a fixed-amount merchant QR through byte-for-byte', () {
      // A real merchant QR: signed (`sign`), merchant mode/code. Dropping any of
      // these makes the payee bank reject it as "not accepting payments".
      const raw =
          'upi://pay?pa=chai@okhdfc&pn=Chai%20Point&am=240.00&cu=INR&mc=5499&mode=02&orgid=159761&sign=AbC123%2Fxy%2Bz%3D';
      final req = parseUpi(raw)!;
      // Fixed amount → the sheet passes amount:null → must be unchanged.
      expect(buildUpiUri(req, amount: null), raw);
    });

    test('keeps sign/mode/mc when injecting an entered amount (open QR)', () {
      const raw =
          'upi://pay?pa=chai@okhdfc&pn=Shop&mc=5499&mode=02&sign=Zm9v%2Bbar%2F1%3D';
      final req = parseUpi(raw)!;
      final out = buildUpiUri(req, amount: 50);
      expect(out, contains('sign=Zm9v%2Bbar%2F1%3D')); // base64 untouched
      expect(out, contains('mode=02'));
      expect(out, contains('mc=5499'));
      expect(out, contains('am=50.00'));
      // VPA keeps its literal '@' (what real scanners send), not '%40'.
      expect(out, startsWith('upi://pay?pa=chai@okhdfc'));
    });

    test('adds cu=INR only when the QR omits it', () {
      final withCu = buildUpiUri(parseUpi('upi://pay?pa=a@bank&cu=INR')!, amount: 10);
      expect('cu='.allMatches(withCu).length, 1);
      final noCu = buildUpiUri(parseUpi('upi://pay?pa=a@bank')!, amount: 10);
      expect(noCu, contains('cu=INR'));
    });

    test('overrides the QR amount with the entered one, no duplicate am', () {
      final out = buildUpiUri(parseUpi('upi://pay?pa=a@bank&am=10')!, amount: 99);
      expect(out, contains('am=99.00'));
      expect('am='.allMatches(out).length, 1);
    });
  });
}
