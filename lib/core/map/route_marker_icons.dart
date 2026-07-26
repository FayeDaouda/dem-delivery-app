import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Marqueurs "départ"/"destination" dessinés à la main — remplacent la
/// goutte Google Maps par défaut (générique, identique dans toutes les apps)
/// par un design propre à DEM, réutilisable sur tous les écrans de trajet
/// (création de commande, suivi, confirmation).
class RouteMarkerIcons {
  const RouteMarkerIcons._();

  /// Fraction verticale de la pointe du pin dans le bitmap — à passer en
  /// `Marker.anchor` pour que la pointe touche exactement la coordonnée
  /// (l'ancrage par défaut de google_maps_flutter, (0.5, 1.0), pointerait
  /// sous le bitmap puisque celui-ci réserve de la marge pour l'ombre).
  static const pinAnchor = Offset(0.5, 0.93);

  /// Marqueur "départ" — pastille pleine ancrée sur son centre, avec une
  /// icône colis (l'app ne fait que de la livraison pour l'instant — pas
  /// besoin d'un pin neutre réutilisable pour un futur trajet passager).
  static Future<BitmapDescriptor> pickup(Color color) => _buildDot(color, Icons.inventory_2_rounded);

  /// Marqueur "destination" — pin classique en goutte avec un drapeau
  /// d'arrivée (façon Waze), ancré sur sa pointe.
  static Future<BitmapDescriptor> delivery(Color color) => _buildPin(color, Icons.sports_score_rounded);

  /// Peint une icône Material centrée sur [center] — technique standard pour
  /// dessiner un glyphe d'icône sur un `Canvas` (le champ de police est celui
  /// déjà embarqué par Flutter pour Material Icons, aucun asset à charger).
  static void _paintIcon(Canvas canvas, IconData icon, Offset center, double size, Color color) {
    final painter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      )
      ..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  static Future<BitmapDescriptor> _buildDot(Color color, IconData icon) async {
    const double size = 72;
    const double c = size / 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawCircle(
      const Offset(c, c + 2),
      19,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.20)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5),
    );
    canvas.drawCircle(const Offset(c, c), 19, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(c, c), 15.5, Paint()..color = color);
    _paintIcon(canvas, icon, const Offset(c, c), 17, Colors.white);

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), width: 46, height: 46);
  }

  static Future<BitmapDescriptor> _buildPin(Color color, IconData icon) async {
    const double w = 64;
    const double h = 84;
    const double cx = w / 2;
    const double headR = 20;
    const double headCy = headR + 6;
    const double tipY = h - 6;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Ombre au sol, sous la pointe
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(cx, tipY + 2), width: 18, height: 6),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.20)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3),
    );

    // Forme goutte = union d'un cercle (tête) et d'un triangle (pointe)
    final headPath = Path()..addOval(Rect.fromCircle(center: const Offset(cx, headCy), radius: headR));
    final tailPath = Path()
      ..moveTo(cx - headR * 0.55, headCy + headR * 0.75)
      ..lineTo(cx, tipY)
      ..lineTo(cx + headR * 0.55, headCy + headR * 0.75)
      ..close();
    final pinPath = Path.combine(ui.PathOperation.union, headPath, tailPath);

    canvas.drawPath(pinPath, Paint()..color = color);
    canvas.drawPath(
      pinPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    _paintIcon(canvas, icon, const Offset(cx, headCy), 18, Colors.white);

    final picture = recorder.endRecording();
    final img = await picture.toImage(w.toInt(), h.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), width: 32, height: 42);
  }
}
