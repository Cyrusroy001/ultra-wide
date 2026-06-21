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

  testWidgets('image-pay buttons are disabled until a valid amount is entered',
      (tester) async {
    final verdict = validateUpi('upi://pay?pa=anand@okhdfc&pn=Anand');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VerifySheet(
          verdict: verdict,
          onPay: (_, _) async {},
          onSaveQr: (_, _) async {},
          onShareQr: (_, _) async {},
        ),
      ),
    ));

    OutlinedButton saveBtn() =>
        tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Save QR'));
    expect(saveBtn().onPressed, isNull); // no amount yet

    await tester.tap(find.text('5'));
    await tester.pump();
    expect(saveBtn().onPressed, isNotNull); // ₹5 is valid and under the cap
  });

  testWidgets('over ₹2,000 disables image-pay and warns, intent Pay stays enabled',
      (tester) async {
    final verdict = validateUpi('upi://pay?pa=anand@okhdfc&pn=Anand');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VerifySheet(
          verdict: verdict,
          onPay: (_, _) async {},
          onSaveQr: (_, _) async {},
          onShareQr: (_, _) async {},
        ),
      ),
    ));

    for (final d in ['3', '0', '0', '0']) {
      await tester.tap(find.text(d));
    }
    await tester.pump();

    expect(find.textContaining('Over ₹2,000'), findsOneWidget);
    expect(
        tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Save QR')).onPressed,
        isNull);
    // The intent path is the only FilledButton and must remain usable.
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
  });

  testWidgets('Save QR calls onSaveQr with the built upi uri and the scan entry',
      (tester) async {
    String? gotUri;
    var gotVpa = '';
    double? gotAmount;
    final verdict = validateUpi('upi://pay?pa=anand@okhdfc&pn=Anand');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VerifySheet(
          verdict: verdict,
          onPay: (_, _) async {},
          onSaveQr: (u, e) async {
            gotUri = u;
            gotVpa = e.vpa;
            gotAmount = e.amount;
          },
          onShareQr: (_, _) async {},
        ),
      ),
    ));

    await tester.tap(find.text('5'));
    await tester.pump();
    final saveBtn = find.widgetWithText(OutlinedButton, 'Save QR');
    await tester.ensureVisible(saveBtn); // sheet scrolls; button sits at the bottom
    await tester.tap(saveBtn);
    await tester.pump();

    expect(gotUri, contains('pa=anand@okhdfc'));
    expect(gotUri, contains('am=5.00'));
    expect(gotVpa, 'anand@okhdfc');
    expect(gotAmount, 5);
  });
}
