import 'dart:async';

import 'lens_controller.dart';

/// In-memory [LensController] for widget tests. Lets a test emit decoded QR
/// strings without any platform/camera.
class FakeLensController implements LensController {
  final _controller = StreamController<String>.broadcast();
  bool started = false;
  bool torch = false;

  void emit(String value) => _controller.add(value);

  @override
  Future<List<CameraInfo>> enumerateCameras() async => const [
        CameraInfo(
          id: '2',
          isBackFacing: true,
          minFocalLengthMm: 1.74,
          hasFlash: false,
          hasAutofocus: false,
          maxZoom: 8,
        ),
      ];

  @override
  Future<int> start(String cameraId) async {
    started = true;
    return 1;
  }

  @override
  Future<void> stop() async => started = false;

  @override
  Future<void> setTorch(bool on) async => torch = on;

  @override
  Future<void> setZoom(double value) async {}

  @override
  Future<void> focusAt(double x, double y) async {}

  @override
  Stream<String> get barcodes => _controller.stream;

  void dispose() => _controller.close();
}
