import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Icône du marqueur "position du livreur" sur la carte — halo, ombre portée
/// et flèche en dégradé. Partagée par les 3 écrans de navigation livreur pour
/// que le marqueur ait la même apparence partout (accueil, course simple,
/// tournée batch), au lieu de trois dessins Canvas divergents.
Future<BitmapDescriptor> buildDriverMarkerIcon() async {
  const double size = 128;
  const double cx = size / 2;
  const double cy = size / 2;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  // Halo externe
  canvas.drawCircle(const Offset(cx, cy), 48, Paint()..color = const Color(0x2533BCD4));
  canvas.drawCircle(const Offset(cx, cy), 36, Paint()..color = const Color(0x4033BCD4));

  // Ombre portée
  final shadowPaint = Paint()
    ..color = const Color(0x6000B4C8)
    ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6);
  final shadowPath = Path()
    ..moveTo(cx, cy - 22 + 4)
    ..lineTo(cx + 16, cy + 14 + 4)
    ..lineTo(cx, cy + 8 + 4)
    ..lineTo(cx - 16, cy + 14 + 4)
    ..close();
  canvas.drawPath(shadowPath, shadowPaint);

  // Cercle de base blanc 3D
  canvas.drawCircle(const Offset(cx, cy + 4), 20, Paint()..color = const Color(0xFFFFFFFF));
  canvas.drawCircle(const Offset(cx, cy + 4), 18, Paint()..color = const Color(0xFF1AB8CC));

  // Flèche de navigation avec gradient 3D
  final arrowPath = Path()
    ..moveTo(cx, cy - 22)
    ..lineTo(cx + 15, cy + 12)
    ..lineTo(cx, cy + 6)
    ..lineTo(cx - 15, cy + 12)
    ..close();

  canvas.drawPath(
    arrowPath,
    Paint()
      ..shader = ui.Gradient.linear(
        const Offset(cx, cy - 22),
        const Offset(cx, cy + 12),
        [const Color(0xFF5EEEFF), const Color(0xFF00A8C0)],
      ),
  );
  canvas.drawPath(
    arrowPath,
    Paint()
      ..color = const Color(0xCCFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0,
  );

  final picture = recorder.endRecording();
  final img = await picture.toImage(size.toInt(), size.toInt());
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), width: 56, height: 56);
}
