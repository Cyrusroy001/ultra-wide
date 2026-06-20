import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/tokens.dart';
import 'lens_controller.dart';

/// Make-or-break diagnostic screen.
///
/// Proves on the real S21 FE that we can: (1) enumerate the physical cameras,
/// (2) auto-pick the true 0.5x ultrawide (shortest focal length among back
/// cameras), (3) open it natively and show a LIVE preview (not the dead main
/// lens's black frame), and (4) decode a UPI QR from that lens.
///
/// If auto-pick lands the wrong camera, tap another row to switch — the column
/// that finally shows a live 0.5x view is the ultrawide's physical id.
class CameraProbeScreen extends StatefulWidget {
  const CameraProbeScreen({super.key, this.lens});

  /// Injected in tests; defaults to the real [NativeLens] at runtime.
  final LensController? lens;

  @override
  State<CameraProbeScreen> createState() => _CameraProbeScreenState();
}

class _CameraProbeScreenState extends State<CameraProbeScreen> {
  late final LensController _lens = widget.lens ?? NativeLens();

  String _status = 'Requesting camera permission…';
  List<CameraInfo> _cameras = const [];
  CameraInfo? _active;
  int? _textureId;
  StreamSubscription<String>? _sub;

  final List<String> _decoded = [];
  int _decodeCount = 0;
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final granted = await Permission.camera.request();
    if (!granted.isGranted) {
      setState(() => _status =
          'Camera permission denied. Enable it in Settings, then reopen.');
      return;
    }
    _sub = _lens.barcodes.listen(_onBarcode);
    try {
      final cams = await _lens.enumerateCameras();
      final pick = pickUltrawide(cams);
      setState(() {
        _cameras = cams;
        _status = cams.isEmpty
            ? 'No cameras reported by the OS.'
            : 'Enumerated ${cams.length} cameras. Auto-picked ${pick?.id ?? "none"}.';
      });
      if (pick != null) await _switchTo(pick);
    } catch (e) {
      setState(() => _status = 'enumerate/start failed: $e');
    }
  }

  Future<void> _switchTo(CameraInfo cam) async {
    setState(() {
      _active = cam;
      _torchOn = false;
      _status = 'Starting camera ${cam.id} '
          '(${cam.minFocalLengthMm.toStringAsFixed(2)}mm)…';
    });
    try {
      final id = await _lens.start(cam.id);
      if (!mounted) return;
      setState(() {
        _textureId = id;
        _status = 'Live on camera ${cam.id}. '
            'Is this the 0.5x ultrawide? Point at a UPI QR.';
      });
    } catch (e) {
      setState(() => _status = 'start(${cam.id}) failed: $e');
    }
  }

  void _onBarcode(String value) {
    setState(() {
      _decodeCount++;
      if (_decoded.isEmpty || _decoded.first != value) {
        _decoded.insert(0, value);
        if (_decoded.length > 5) _decoded.removeLast();
      }
    });
  }

  Future<void> _toggleTorch() async {
    final next = !_torchOn;
    await _lens.setTorch(next);
    setState(() => _torchOn = next);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _lens.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.ink,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_textureId != null)
              Texture(textureId: _textureId!)
            else
              const ColoredBox(color: Colors.black),
            _scrim(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  const SizedBox(height: 12),
                  _cameraList(),
                  const Spacer(),
                  _decodedPanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scrim() => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black54, Colors.transparent, Colors.black87],
            stops: [0.0, 0.4, 1.0],
          ),
        ),
      );

  Widget _header() => Row(
        children: [
          const Text('scan·pay',
              style: TextStyle(
                  fontFamily: AppTokens.mono,
                  letterSpacing: 2,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.cloud)),
          const SizedBox(width: 8),
          const Text('camera probe',
              style: TextStyle(
                  fontFamily: AppTokens.mono,
                  fontSize: 12,
                  color: AppTokens.mist)),
          const Spacer(),
          if (_active?.hasFlash == true)
            IconButton(
              onPressed: _toggleTorch,
              icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off,
                  color: _torchOn ? AppTokens.amber : AppTokens.mist),
            ),
        ],
      );

  Widget _cameraList() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.slate.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: AppTokens.slateSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_status,
              style: const TextStyle(color: AppTokens.cloud, fontSize: 13)),
          const SizedBox(height: 8),
          ..._cameras.map(_cameraRow),
          if (_cameras.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('—',
                  style: TextStyle(color: AppTokens.mist, fontFamily: AppTokens.mono)),
            ),
        ],
      ),
    );
  }

  Widget _cameraRow(CameraInfo cam) {
    final isActive = _active?.id == cam.id;
    final isUltrawideGuess = pickUltrawide(_cameras)?.id == cam.id;
    return InkWell(
      onTap: () => _switchTo(cam),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              isActive ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 16,
              color: isActive ? AppTokens.lime : AppTokens.mist,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                cam.toString(),
                style: TextStyle(
                  fontFamily: AppTokens.mono,
                  fontSize: 12,
                  color: isActive ? AppTokens.lime : AppTokens.cloud,
                ),
              ),
            ),
            if (isUltrawideGuess)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTokens.lime.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('ultrawide?',
                    style: TextStyle(
                        fontFamily: AppTokens.mono,
                        fontSize: 10,
                        color: AppTokens.lime)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _decodedPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTokens.slate.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: AppTokens.slateSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('decoded',
                  style: TextStyle(
                      fontFamily: AppTokens.mono,
                      fontSize: 12,
                      color: AppTokens.mist)),
              const Spacer(),
              Text('$_decodeCount hits',
                  style: const TextStyle(
                      fontFamily: AppTokens.mono,
                      fontSize: 12,
                      color: AppTokens.mist)),
            ],
          ),
          const SizedBox(height: 6),
          if (_decoded.isEmpty)
            const Text('Point the lens at a UPI QR…',
                style: TextStyle(color: AppTokens.mist, fontSize: 13))
          else
            ..._decoded.map((d) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    d,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTokens.mono,
                      fontSize: 12,
                      color: d.startsWith('upi://')
                          ? AppTokens.lime
                          : AppTokens.amber,
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}
