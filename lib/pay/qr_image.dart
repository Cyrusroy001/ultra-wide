import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

/// Renders [upiUri] to a PNG QR with a WHITE background and a quiet-zone border
/// so any UPI app's gallery scanner can read it. Black modules on white — never
/// transparent (transparent gaps make scanners fail). Pure local rendering,
/// no network.
Future<Uint8List> renderUpiQrPng(
  String upiUri, {
  double size = 1024,
  double quietZone = 48,
}) async {
  final painter = QrPainter(
    data: upiUri,
    version: QrVersions.auto,
    gapless: true,
    eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square, color: Color(0xFF000000)),
    dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square, color: Color(0xFF000000)),
  );

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));
  canvas.drawRect(
      Rect.fromLTWH(0, 0, size, size), Paint()..color = const Color(0xFFFFFFFF));
  canvas.translate(quietZone, quietZone);
  painter.paint(canvas, Size(size - quietZone * 2, size - quietZone * 2));

  final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// Saves [png] to the device gallery (MediaStore). Throws on permission denial;
/// the caller surfaces a snackbar.
Future<void> saveQrToGallery(Uint8List png,
    {String filename = 'ultrawide_upi_qr'}) async {
  await Gal.putImageBytes(png, name: filename);
}

/// Writes [png] to a temp file and opens the system share sheet so the user can
/// send the QR to a UPI app (e.g. WhatsApp). [text] is the accompanying message.
Future<void> shareQr(Uint8List png, {required String text}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/ultrawide_upi_qr.png');
  await file.writeAsBytes(png);
  await SharePlus.instance
      .share(ShareParams(text: text, files: [XFile(file.path)]));
}
