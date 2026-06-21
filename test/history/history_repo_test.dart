import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scanpay/data/prefs.dart';
import 'package:scanpay/pay/categories.dart';
import 'package:scanpay/history/history_repo.dart';

ScanEntry entry(int t, {double? amt}) => ScanEntry(
      vpa: 'a@b',
      name: 'A',
      amount: amt,
      category: PayCategory.food,
      timeMillis: t,
    );

Future<HistoryRepo> freshRepo() async {
  SharedPreferences.setMockInitialValues({});
  return HistoryRepo(Prefs(await SharedPreferences.getInstance()));
}

void main() {
  test('prepends newest first and caps at 200', () async {
    final repo = await freshRepo();
    for (var i = 0; i < 205; i++) {
      await repo.add(entry(i));
    }
    final list = await repo.list();
    expect(list.length, 200);
    expect(list.first.timeMillis, 204); // newest first
  });

  test('markPaid flips the flag', () async {
    final repo = await freshRepo();
    await repo.add(entry(1));
    await repo.markPaid(1, true);
    expect((await repo.list()).first.paid, isTrue);
  });

  test('summary sums only known amounts', () async {
    final repo = await freshRepo();
    final now = DateTime.now().millisecondsSinceEpoch;
    await repo.add(entry(now, amt: 100));
    await repo.add(entry(now + 1, amt: null));
    final s = await repo.summary();
    expect(s.knownAmountSum, 100);
    expect(s.countThisMonth, 2);
    expect(s.topCategory, PayCategory.food);
  });

  test('clear empties the log', () async {
    final repo = await freshRepo();
    await repo.add(entry(1));
    await repo.clear();
    expect(await repo.list(), isEmpty);
  });

  test('delete removes only the matching entry', () async {
    final repo = await freshRepo();
    await repo.add(entry(1));
    await repo.add(entry(2)); // list: [2, 1]
    await repo.delete(1);
    final list = await repo.list();
    expect(list.length, 1);
    expect(list.first.timeMillis, 2);
  });

  test('restore re-inserts keeping newest-first by time', () async {
    final repo = await freshRepo();
    await repo.add(entry(1));
    await repo.add(entry(3)); // list: [3, 1]
    await repo.restore(entry(2)); // belongs between 3 and 1
    expect((await repo.list()).map((e) => e.timeMillis), [3, 2, 1]);
  });
}
