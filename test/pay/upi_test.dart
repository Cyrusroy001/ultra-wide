import 'package:flutter_test/flutter_test.dart';
import 'package:scanpay/pay/upi.dart';

void main() {
  test('parses a standard pay uri', () {
    final r = parseUpi(
        'upi://pay?pa=anand@okhdfc&pn=Anand%20Tea&am=240.00&cu=INR&tn=Chai')!;
    expect(r.action, 'pay');
    expect(r.payeeVpa, 'anand@okhdfc');
    expect(r.payeeName, 'Anand Tea');
    expect(r.amount, 240.0);
    expect(r.note, 'Chai');
  });

  test('open-amount uri has null amount', () {
    expect(parseUpi('upi://pay?pa=a@b')!.amount, isNull);
  });

  test('collect uri keeps action=collect', () {
    expect(parseUpi('upi://collect?pa=a@b')!.action, 'collect');
  });

  test('non-upi or missing pa returns null', () {
    expect(parseUpi('https://example.com'), isNull);
    expect(parseUpi('upi://pay?pn=NoVpa'), isNull);
  });

  test('keeps the exact scanned string in raw (signature survives intact)', () {
    const raw = 'upi://pay?pa=shop@okhdfc&pn=Shop&sign=Zm9v%2Bbar%2F1%3D&mode=02';
    expect(parseUpi('  $raw  ')!.raw, raw); // trimmed, otherwise byte-identical
  });
}
