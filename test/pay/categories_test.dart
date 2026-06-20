import 'package:flutter_test/flutter_test.dart';
import 'package:scanpay/pay/categories.dart';

void main() {
  test('maps MCC to category', () {
    expect(categorize(merchantCode: '5814'), PayCategory.food);
    expect(categorize(merchantCode: '5541'), PayCategory.travel);
  });

  test('keyword-matches payee name when no MCC', () {
    expect(categorize(payeeName: 'Swiggy Instamart'), PayCategory.food);
    expect(categorize(payeeName: 'IRCTC'), PayCategory.travel);
    expect(categorize(payeeName: 'Zepto'), PayCategory.shopping);
    expect(categorize(payeeName: 'DTH Recharge'), PayCategory.bills);
  });

  test('falls back to other', () {
    expect(categorize(payeeName: 'Unknown Vendor xyz'), PayCategory.other);
    expect(categorize(), PayCategory.other);
  });
}
