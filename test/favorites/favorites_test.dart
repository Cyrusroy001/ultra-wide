import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scanpay/data/prefs.dart';
import 'package:scanpay/favorites/favorites.dart';

void main() {
  test('add, dedupe by vpa, remove', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = FavoritesRepo(Prefs(await SharedPreferences.getInstance()));
    await repo.add(const Favorite(vpa: 'a@b', name: 'A'));
    await repo.add(const Favorite(vpa: 'a@b', name: 'A2')); // dedupe by vpa
    final after = await repo.list();
    expect(after.length, 1);
    expect(after.first.name, 'A2'); // newest wins, moved to front
    await repo.remove('a@b');
    expect(await repo.list(), isEmpty);
  });

  test('most recently added is first', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = FavoritesRepo(Prefs(await SharedPreferences.getInstance()));
    await repo.add(const Favorite(vpa: 'a@b', name: 'A'));
    await repo.add(const Favorite(vpa: 'c@d', name: 'C'));
    expect((await repo.list()).first.vpa, 'c@d');
  });
}
