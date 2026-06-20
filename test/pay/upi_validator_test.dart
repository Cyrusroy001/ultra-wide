import 'package:flutter_test/flutter_test.dart';
import 'package:scanpay/pay/upi_validator.dart';

void main() {
  test('clean pay uri is ok', () {
    final v = validateUpi('upi://pay?pa=anand@okhdfc&pn=Anand&am=240&cu=INR');
    expect(v.safety, UpiSafety.ok);
    expect(v.request!.payeeVpa, 'anand@okhdfc');
  });

  test('collect request is blocked', () {
    final v = validateUpi('upi://collect?pa=scam@x&am=999');
    expect(v.safety, UpiSafety.blocked);
    expect(v.reason, contains('collect'));
  });

  test('non-upi is blocked', () {
    expect(validateUpi('http://x').safety, UpiSafety.blocked);
  });

  test('invalid vpa is blocked', () {
    expect(validateUpi('upi://pay?pa=notavpa').safety, UpiSafety.blocked);
  });

  test('malformed amount is blocked', () {
    expect(validateUpi('upi://pay?pa=a@b&am=12.999').safety, UpiSafety.blocked);
    expect(validateUpi('upi://pay?pa=a@b&am=-5').safety, UpiSafety.blocked);
  });

  test('non-INR currency is caution', () {
    expect(validateUpi('upi://pay?pa=a@b&am=10&cu=USD').safety, UpiSafety.caution);
  });

  test('large amount guard', () {
    expect(isLargeAmount(6000), isTrue);
    expect(isLargeAmount(100), isFalse);
  });
}
