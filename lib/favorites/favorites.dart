import 'dart:convert';

import '../data/prefs.dart';

class Favorite {
  final String vpa;
  final String name;
  final String? note;

  const Favorite({required this.vpa, required this.name, this.note});

  Map<String, dynamic> toJson() => {'vpa': vpa, 'name': name, 'note': note};

  factory Favorite.fromJson(Map<String, dynamic> j) =>
      Favorite(vpa: j['vpa'], name: j['name'], note: j['note']);
}

/// Saved payees for the Quick-Pay strip. Local only; can only ever hold payees
/// the user scanned or typed (the app can't read other apps' contacts).
class FavoritesRepo {
  final Prefs _p;
  FavoritesRepo(this._p);

  Future<List<Favorite>> list() async {
    final s = _p.getString(PrefKeys.favorites);
    if (s == null) return [];
    return (jsonDecode(s) as List)
        .map((e) => Favorite.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _save(List<Favorite> items) => _p.setString(
        PrefKeys.favorites,
        jsonEncode(items.map((e) => e.toJson()).toList()),
      );

  /// Adds (or moves to front) a favorite, de-duped by VPA.
  Future<void> add(Favorite f) async {
    final items = await list()..removeWhere((e) => e.vpa == f.vpa);
    items.insert(0, f);
    await _save(items);
  }

  Future<void> remove(String vpa) async {
    final items = await list()..removeWhere((e) => e.vpa == vpa);
    await _save(items);
  }
}
