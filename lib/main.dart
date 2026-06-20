import 'package:flutter/material.dart';

import 'scan/camera_probe.dart';
import 'theme/tokens.dart';

void main() => runApp(const ScanPayApp());

class ScanPayApp extends StatelessWidget {
  const ScanPayApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ScanPay',
        debugShowCheckedModeBanner: false,
        theme: AppTokens.buildTheme(),
        // Phase 1 gate: prove the native ultrawide on-device before the
        // real scan flow is wired in. Swapped for the home shell post-gate.
        home: const CameraProbeScreen(),
      );
}
