import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scanpay/data/prefs.dart';
import 'package:scanpay/pay/categories.dart';
import 'package:scanpay/history/history_repo.dart';
import 'package:scanpay/history/history_screen.dart';

ScanEntry entry(int t, {double? amt}) => ScanEntry(
      vpa: 'a@b',
      name: 'Anand',
      amount: amt,
      category: PayCategory.food,
      timeMillis: t,
    );

Future<HistoryRepo> repoWith(List<ScanEntry> entries) async {
  SharedPreferences.setMockInitialValues({});
  final repo = HistoryRepo(Prefs(await SharedPreferences.getInstance()));
  for (final e in entries.reversed) {
    await repo.add(e); // add prepends, so reverse keeps given order
  }
  return repo;
}

Future<void> pumpHistory(WidgetTester tester, HistoryRepo repo) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: HistoryScreen(repo: repo))),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('explicit Mark paid control flips the entry to paid', (tester) async {
    final repo = await repoWith([entry(1, amt: 10)]);
    await pumpHistory(tester, repo);

    expect(find.text('Mark paid'), findsOneWidget);
    await tester.tap(find.text('Mark paid'));
    await tester.pumpAndSettle();

    expect(find.text('Paid'), findsOneWidget);
    expect((await repo.list()).single.paid, isTrue);
  });

  testWidgets('delete button removes the scan from the log', (tester) async {
    final repo = await repoWith([entry(1, amt: 10)]);
    await pumpHistory(tester, repo);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(await repo.list(), isEmpty);
    expect(find.text('No scans yet.'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget); // delete is undoable

    // Drain the SnackBar's auto-dismiss timer so the test leaves none pending.
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}
