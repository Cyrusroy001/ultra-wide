import 'package:flutter/services.dart';

/// Metadata for one physical camera, as reported by the native enumeration.
class CameraInfo {
  final String id;
  final bool isBackFacing;

  /// Smallest available focal length (mm). The ultrawide is the back camera
  /// with the *shortest* focal length.
  final double minFocalLengthMm;
  final bool hasFlash;
  final bool hasAutofocus;
  final double maxZoom;

  const CameraInfo({
    required this.id,
    required this.isBackFacing,
    required this.minFocalLengthMm,
    required this.hasFlash,
    required this.hasAutofocus,
    required this.maxZoom,
  });

  factory CameraInfo.fromMap(Map<dynamic, dynamic> m) => CameraInfo(
        id: m['id'] as String,
        isBackFacing: m['isBackFacing'] as bool,
        minFocalLengthMm: (m['minFocalLengthMm'] as num).toDouble(),
        hasFlash: m['hasFlash'] as bool,
        hasAutofocus: m['hasAutofocus'] as bool,
        maxZoom: (m['maxZoom'] as num).toDouble(),
      );

  @override
  String toString() =>
      'cam $id ${isBackFacing ? "back" : "front"} '
      '${minFocalLengthMm.toStringAsFixed(2)}mm '
      'flash:$hasFlash af:$hasAutofocus zoom:${maxZoom.toStringAsFixed(1)}x';
}

/// On a phone with a dead main lens, the ultrawide is the working back camera
/// with the shortest focal length. Pure policy so it can be unit-tested.
CameraInfo? pickUltrawide(List<CameraInfo> cameras) {
  final back = cameras.where((c) => c.isBackFacing).toList();
  if (back.isEmpty) return null;
  back.sort((a, b) => a.minFocalLengthMm.compareTo(b.minFocalLengthMm));
  return back.first;
}

/// The one interface the app uses to talk to a camera. The only implementation
/// is [NativeLens]; tests use a fake. No Dart `mobile_scanner`/`camera` path.
abstract class LensController {
  Future<List<CameraInfo>> enumerateCameras();

  /// Starts the given physical camera; returns the Flutter texture id to render.
  Future<int> start(String cameraId);
  Future<void> stop();
  Future<void> setTorch(bool on);
  Future<void> setZoom(double value);
  Future<void> focusAt(double x, double y);

  /// Decoded QR raw strings.
  Stream<String> get barcodes;
}

/// Talks to the native Camera2 + ML Kit driver over platform channels.
class NativeLens implements LensController {
  static const _m = MethodChannel('scanpay/camera');
  static const _e = EventChannel('scanpay/barcodes');

  @override
  Future<List<CameraInfo>> enumerateCameras() async {
    final raw = await _m.invokeMethod<List<dynamic>>('enumerate') ?? const [];
    return raw
        .map((e) => CameraInfo.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  @override
  Future<int> start(String cameraId) async =>
      await _m.invokeMethod<int>('start', {'cameraId': cameraId}) ?? -1;

  @override
  Future<void> stop() => _m.invokeMethod('stop');

  @override
  Future<void> setTorch(bool on) => _m.invokeMethod('torch', {'on': on});

  @override
  Future<void> setZoom(double value) => _m.invokeMethod('zoom', {'value': value});

  @override
  Future<void> focusAt(double x, double y) =>
      _m.invokeMethod('focus', {'x': x, 'y': y});

  @override
  Stream<String> get barcodes =>
      _e.receiveBroadcastStream().map((e) => e as String);
}
