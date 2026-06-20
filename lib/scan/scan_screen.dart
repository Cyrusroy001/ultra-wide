import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../history/history_repo.dart';
import '../pay/launcher.dart';
import '../pay/upi_validator.dart';
import '../pay/verify_sheet.dart';
import '../theme/tokens.dart';
import 'lens_controller.dart';
import 'reticle.dart';

/// The home scanner. Native ultrawide preview under the reticle; every decode
/// runs through [validateUpi] and (if not junk) opens the [VerifySheet]. A
/// payment NEVER fires without that explicit confirm.
class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    this.lens,
    this.history,
    this.rememberedCameraId,
    this.defaultPackage,
    this.largeAmountThreshold = 5000,
  });

  final LensController? lens;
  final HistoryRepo? history;
  final String? rememberedCameraId;
  final String? defaultPackage;
  final double largeAmountThreshold;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late final LensController _lens = widget.lens ?? NativeLens();

  StreamSubscription<String>? _sub;
  Timer? _rejectTimer;
  CameraInfo? _active;
  int? _textureId;
  ReticleState _state = ReticleState.scanning;
  bool _sheetOpen = false;
  bool _denied = false;
  String? _rejectMsg;
  String? _lastValue;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<bool> _ensurePermission() async {
    try {
      final s = await Permission.camera.request();
      return s.isGranted;
    } catch (_) {
      return true; // non-Android / test env: proceed
    }
  }

  Future<void> _bootstrap() async {
    _sub = _lens.barcodes.listen(_onBarcode);
    if (!await _ensurePermission()) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    try {
      final cams = await _lens.enumerateCameras();
      final pick = _rememberedOr(cams) ?? pickUltrawide(cams);
      if (pick == null) return;
      _active = pick;
      final id = await _lens.start(pick.id);
      if (!mounted) return;
      setState(() => _textureId = id);
    } catch (_) {
      // leave preview black; controls degrade gracefully
    }
  }

  CameraInfo? _rememberedOr(List<CameraInfo> cams) {
    final id = widget.rememberedCameraId;
    if (id == null) return null;
    for (final c in cams) {
      if (c.id == id) return c;
    }
    return null;
  }

  void _onBarcode(String value) {
    if (_sheetOpen) return;
    final now = DateTime.now();
    if (value == _lastValue && now.difference(_lastAt) < const Duration(seconds: 2)) {
      return;
    }
    _lastValue = value;
    _lastAt = now;

    final verdict = validateUpi(value);
    // Junk (not even a UPI uri): flash red, show a brief hint, keep scanning.
    if (verdict.safety == UpiSafety.blocked && verdict.request == null) {
      setState(() {
        _state = ReticleState.rejected;
        _rejectMsg = verdict.reason ?? 'Not a UPI payment QR.';
      });
      _rejectTimer?.cancel();
      _rejectTimer = Timer(const Duration(milliseconds: 1100), () {
        if (!mounted) return;
        setState(() {
          _state = ReticleState.scanning;
          _rejectMsg = null;
        });
      });
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() => _state = ReticleState.locked);
    _openSheet(verdict);
  }

  Future<void> _openSheet(UpiVerdict verdict) async {
    _sheetOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => VerifySheet(
        verdict: verdict,
        onPay: _onPay,
        largeAmountThreshold: widget.largeAmountThreshold,
      ),
    );
    _sheetOpen = false;
    if (mounted) setState(() => _state = ReticleState.scanning);
  }

  Future<void> _onPay(String uri, ScanEntry entry) async {
    final res = await launchUpiUri(uri, package: widget.defaultPackage);
    await widget.history?.add(entry);
    if (!mounted) return;
    Navigator.of(context).maybePop();
    _toast(res.launched
        ? 'Opened your UPI app — confirm the payment there.'
        : (res.error ?? 'Could not open a UPI app.'));
  }

  void _toast(String msg) {
    final m = ScaffoldMessenger.maybeOf(context);
    m?.showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _toggleTorch() async {
    final next = !(_torchOn);
    await _lens.setTorch(next);
    setState(() => _torchOn = next);
  }

  bool _torchOn = false;

  @override
  void dispose() {
    _rejectTimer?.cancel();
    _sub?.cancel();
    _lens.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_textureId != null)
          Texture(textureId: _textureId!)
        else
          const ColoredBox(color: Colors.black),
        Reticle(state: _state),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _topBar(),
                const Spacer(),
                if (_denied)
                  _deniedCard()
                else if (_rejectMsg != null)
                  _rejectCard(_rejectMsg!)
                else
                  _hint(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _topBar() => Row(
        children: [
          const Text('ultra·wide',
              style: TextStyle(
                  fontFamily: AppTokens.mono,
                  letterSpacing: 2,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.cloud)),
          const Spacer(),
          if (_active != null) _lensChip(),
          // Torch only if the active lens actually has a flash (ultrawide often doesn't).
          if (_active?.hasFlash == true)
            IconButton(
              onPressed: _toggleTorch,
              icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off,
                  color: _torchOn ? AppTokens.amber : AppTokens.mist),
            ),
        ],
      );

  Widget _lensChip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: AppTokens.slate.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('${_active!.minFocalLengthMm.toStringAsFixed(1)}mm',
            style: const TextStyle(
                fontFamily: AppTokens.mono, fontSize: 11, color: AppTokens.lime)),
      );

  Widget _hint() => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppTokens.ink.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text('Point the ultrawide at a UPI QR to pay',
              style: TextStyle(color: AppTokens.cloud, fontSize: 13)),
        ),
      );

  Widget _rejectCard(String msg) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppTokens.alertRed.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTokens.alertRed.withValues(alpha: 0.5)),
          ),
          child: Text(msg,
              style: const TextStyle(color: AppTokens.alertRed, fontSize: 13)),
        ),
      );

  Widget _deniedCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTokens.slate,
          borderRadius: BorderRadius.circular(AppTokens.radius),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Camera permission is needed to scan.',
                style: TextStyle(color: AppTokens.cloud)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => openAppSettings(),
              child: const Text('Open settings'),
            ),
          ],
        ),
      );
}
