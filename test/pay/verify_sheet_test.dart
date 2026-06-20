import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanpay/pay/upi_validator.dart';
import 'package:scanpay/pay/verify_sheet.dart';

void main() {
  testWidgets('open-amount sheet shows raw VPA and enables Pay once amount entered',
      (tester) async {
    final verdict = validateUpi('upi://pay?pa=anand@okhdfc&pn=Anand');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VerifySheet(verdict: verdict, onPay: (_, _) async {})),
    ));

    expect(find.text('anand@okhdfc'), findsOneWidget); // raw VPA always shown
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

    await tester.tap(find.text('2'));
    await tester.tap(find.text('4'));
    await tester.tap(find.text('0'));
    await tester.pump();

    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
  });

  testWidgets('blocked verdict shows red reason and no Pay button', (tester) async {
    final verdict = validateUpi('upi://collect?pa=scam@x');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VerifySheet(verdict: verdict, onPay: (_, _) async {})),
    ));

    expect(find.textContaining('collect'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('fixed-amount sheet is pre-enabled and labels the merchant amount',
      (tester) async {
    final verdict = validateUpi('upi://pay?pa=anand@okhdfc&pn=Anand&am=240');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VerifySheet(verdict: verdict, onPay: (_, _) async {})),
    ));

    expect(find.textContaining('set by merchant'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
  });
}
