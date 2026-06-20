import 'package:flutter/material.dart';

import '../pay/categories.dart';

/// Accent colour for a spend category.
Color categoryColor(PayCategory c) => switch (c) {
      PayCategory.food => AppTokens.catFood,
      PayCategory.travel => AppTokens.catTravel,
      PayCategory.shopping => AppTokens.catShop,
      PayCategory.bills => AppTokens.catBills,
      PayCategory.other => AppTokens.catOther,
    };

/// Centralised colours + theme for ScanPay. Dark, scanner-first.
class AppTokens {
  static const ink = Color(0xFF0B0E11);
  static const slate = Color(0xFF161B22);
  static const slateSoft = Color(0xFF1F2630);
  static const mist = Color(0xFF8B98A5);
  static const cloud = Color(0xFFE6EDF3);
  static const lime = Color(0xFFB6FF3A);
  static const amber = Color(0xFFFFB627);
  static const alertRed = Color(0xFFFF5C5C);

  static const catFood = Color(0xFFFF7A59);
  static const catTravel = Color(0xFF4FC3F7);
  static const catShop = Color(0xFFB6FF3A);
  static const catBills = Color(0xFFFFB627);
  static const catOther = Color(0xFF8B98A5);

  static const radius = 18.0;

  static const mono = 'monospace';

  static ThemeData buildTheme() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: ink,
      colorScheme: base.colorScheme.copyWith(
        surface: slate,
        primary: lime,
        secondary: amber,
        error: alertRed,
        onPrimary: ink,
        onSurface: cloud,
      ),
      textTheme: base.textTheme.apply(bodyColor: cloud, displayColor: cloud),
    );
  }
}
