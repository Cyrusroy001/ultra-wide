import 'package:shared_preferences/shared_preferences.dart';

/// Centralised pref keys so they're never stringly-typed at call sites.
class PrefKeys {
  static const cameraId = 'camera_id';
  static const defaultUpiPackage = 'default_upi_package';
  static const largeAmountThreshold = 'large_amount_threshold';
  static const beepOnLock = 'beep_on_lock';
  static const favorites = 'favorites_json';
  static const history = 'history_json';
  static const onboarded = 'onboarded';
}

/// Thin typed wrapper over [SharedPreferences] so repos and settings share one
/// surface, and so it can be swapped for a real DB later.
class Prefs {
  final SharedPreferences raw;
  Prefs(this.raw);

  static Future<Prefs> create() async =>
      Prefs(await SharedPreferences.getInstance());

  String? getString(String k) => raw.getString(k);
  Future<void> setString(String k, String v) => raw.setString(k, v);

  bool getBool(String k, {bool def = false}) => raw.getBool(k) ?? def;
  Future<void> setBool(String k, bool v) => raw.setBool(k, v);

  double getDouble(String k, {double def = 0}) => raw.getDouble(k) ?? def;
  Future<void> setDouble(String k, double v) => raw.setDouble(k, v);

  Future<void> remove(String k) => raw.remove(k);
}
