import 'package:flutter_test/flutter_test.dart';
import 'package:scanpay/pay/upi.dart';
import 'package:scanpay/pay/launcher.dart';

void main() {
  const base = UpiRequest(action: 'pay', payeeVpa: 'a@bank', payeeName: 'A B');

  test('builds uri with entered amount, INR, encoded fields', () {
    expect(buildUpiUri(base, amount: 240),
        'upi://pay?pa=a%40bank&pn=A%20B&am=240.00&cu=INR');
  });

  test('omits am when amount null (open)', () {
    expect(buildUpiUri(base), 'upi://pay?pa=a%40bank&pn=A%20B&cu=INR');
  });

  test('entered amount overrides the QR amount', () {
    const fixed = UpiRequest(action: 'pay', payeeVpa: 'a@bank', amount: 10);
    expect(buildUpiUri(fixed, amount: 99), contains('am=99.00'));
  });
}
