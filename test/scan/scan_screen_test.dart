import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanpay/scan/fake_lens.dart';
import 'package:scanpay/scan/scan_screen.dart';

// NOTE: the Reticle animates forever, so pumpAndSettle() would never return.
// Drive the clock with explicit pump(duration) calls instead.
void main() {
  testWidgets('emitting a valid UPI QR opens the verify sheet', (tester) async {
    final lens = FakeLensController();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ScanScreen(lens: lens))));
    await tester.pump(); // kick bootstrap
    await tester.pump(const Duration(milliseconds: 50)); // resolve enumerate/start

    lens.emit('upi://pay?pa=anand@okhdfc&pn=Anand');
    await tester.pump(); // deliver stream event -> push the sheet route
    await tester.pump(const Duration(milliseconds: 400)); // sheet animates in

    expect(find.text('anand@okhdfc'), findsOneWidget); // raw VPA in the sheet
    lens.dispose();
  });

  testWidgets('a non-UPI QR does not open the sheet and shows a hint', (tester) async {
    final lens = FakeLensController();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ScanScreen(lens: lens))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    lens.emit('https://example.com');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('anand@okhdfc'), findsNothing);
    expect(find.textContaining('UPI'), findsWidgets); // reject hint mentions UPI

    await tester.pump(const Duration(milliseconds: 1200)); // flush reject timer
    lens.dispose();
  });
}
