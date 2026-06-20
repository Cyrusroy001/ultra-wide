import 'package:flutter/material.dart';

import 'data/prefs.dart';
import 'history/history_repo.dart';
import 'history/history_screen.dart';
import 'scan/lens_controller.dart';
import 'scan/scan_screen.dart';
import 'theme/tokens.dart';

class ScanPayApp extends StatelessWidget {
  const ScanPayApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ScanPay',
        debugShowCheckedModeBanner: false,
        theme: AppTokens.buildTheme(),
        home: const HomeShell(),
      );
}

/// Owns the single [NativeLens] + repos and the two-tab nav (Scan / History).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _lens = NativeLens();
  int _tab = 0;
  Prefs? _prefs;
  HistoryRepo? _history;

  @override
  void initState() {
    super.initState();
    Prefs.create().then((p) {
      if (!mounted) return;
      setState(() {
        _prefs = p;
        _history = HistoryRepo(p);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_prefs == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTokens.lime)),
      );
    }
    final prefs = _prefs!;
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          ScanScreen(
            lens: _lens,
            history: _history,
            rememberedCameraId: prefs.getString(PrefKeys.cameraId),
            defaultPackage: prefs.getString(PrefKeys.defaultUpiPackage),
            largeAmountThreshold:
                prefs.getDouble(PrefKeys.largeAmountThreshold, def: 5000),
          ),
          HistoryScreen(repo: _history!),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppTokens.slate,
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.qr_code_scanner), label: 'Scan'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
    );
  }
}
