import 'package:flutter_test/flutter_test.dart';
import 'package:scanpay/pay/gallery_cap.dart';

void main() {
  group('galleryCapExceeded (UPI gallery/image path caps at ₹2,000)', () {
    test('under the cap is allowed', () {
      expect(galleryCapExceeded(10), isFalse);
      expect(galleryCapExceeded(1999.99), isFalse);
    });
    test('exactly ₹2,000 is allowed (boundary)', () {
      expect(galleryCapExceeded(2000), isFalse);
    });
    test('over ₹2,000 is blocked', () {
      expect(galleryCapExceeded(2000.01), isTrue);
      expect(galleryCapExceeded(5000), isTrue);
    });
    test('zero is not "exceeded" (separate empty-amount guard handles it)', () {
      expect(galleryCapExceeded(0), isFalse);
    });
  });
}
