import 'package:flutter_test/flutter_test.dart';
import 'package:scanpay/scan/lens_controller.dart';

CameraInfo cam(String id, bool back, double f) => CameraInfo(
      id: id,
      isBackFacing: back,
      minFocalLengthMm: f,
      hasFlash: back,
      hasAutofocus: true,
      maxZoom: 8,
    );

void main() {
  test('picks back-facing camera with smallest focal length', () {
    final cams = [cam('0', true, 5.2), cam('1', false, 3.0), cam('2', true, 1.8)];
    expect(pickUltrawide(cams)!.id, '2');
  });

  test('ignores front cameras even if shorter focal length', () {
    final cams = [cam('0', true, 5.2), cam('1', false, 1.0)];
    expect(pickUltrawide(cams)!.id, '0');
  });

  test('returns null when no back camera', () {
    expect(pickUltrawide([cam('1', false, 1.0)]), isNull);
  });

  test('CameraInfo.fromMap round-trips native payload', () {
    final c = CameraInfo.fromMap({
      'id': '2',
      'isBackFacing': true,
      'minFocalLengthMm': 1.8,
      'hasFlash': false,
      'hasAutofocus': false,
      'maxZoom': 4.0,
    });
    expect(c.id, '2');
    expect(c.isBackFacing, true);
    expect(c.minFocalLengthMm, 1.8);
    expect(c.hasFlash, false);
  });
}
