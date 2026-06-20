import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanpay/scan/reticle.dart';
import 'package:scanpay/theme/tokens.dart';

void main() {
  test('reticle color reflects state', () {
    expect(reticleColor(ReticleState.scanning), AppTokens.lime);
    expect(reticleColor(ReticleState.locked), AppTokens.amber);
    expect(reticleColor(ReticleState.rejected), AppTokens.alertRed);
  });

  testWidgets('reticle builds for each state', (tester) async {
    for (final s in ReticleState.values) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Reticle(state: s))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(Reticle), findsOneWidget);
    }
  });
}
