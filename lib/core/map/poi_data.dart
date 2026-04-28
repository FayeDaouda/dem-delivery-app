import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ── Catégories de POI ─────────────────────────────────────────────────────────
enum PoiCategory {
  quartier,
  hopital,
  marche,
  ecole,
  stationBus,
  stationEssence,
}

extension PoiCategoryX on PoiCategory {
  String get label {
    switch (this) {
      case PoiCategory.quartier:      return 'Quartier';
      case PoiCategory.hopital:       return 'Hôpital';
      case PoiCategory.marche:        return 'Marché';
      case PoiCategory.ecole:         return 'École / Université';
      case PoiCategory.stationBus:    return 'Gare / Transport';
      case PoiCategory.stationEssence:return 'Station essence';
    }
  }

  Color get color {
    switch (this) {
      case PoiCategory.quartier:      return const Color(0xFF607D8B); // gris-bleu
      case PoiCategory.hopital:       return const Color(0xFFE53935); // rouge
      case PoiCategory.marche:        return const Color(0xFFFF9800); // orange
      case PoiCategory.ecole:         return const Color(0xFF1565C0); // bleu foncé
      case PoiCategory.stationBus:    return const Color(0xFF00897B); // teal
      case PoiCategory.stationEssence:return const Color(0xFF43A047); // vert
    }
  }

  String get emoji {
    switch (this) {
      case PoiCategory.quartier:      return 'Q';
      case PoiCategory.hopital:       return '+';
      case PoiCategory.marche:        return 'M';
      case PoiCategory.ecole:         return 'E';
      case PoiCategory.stationBus:    return 'G';
      case PoiCategory.stationEssence:return 'S';
    }
  }
}

// ── Modèle POI ────────────────────────────────────────────────────────────────
class PoiPoint {
  final String id;
  final String name;
  final PoiCategory category;
  final LatLng position;

  const PoiPoint({
    required this.id,
    required this.name,
    required this.category,
    required this.position,
  });
}

// ── Données statiques Dakar ───────────────────────────────────────────────────
const List<PoiPoint> dakarPois = [
  // ── Quartiers ───────────────────────────────────────────────────────────────
  PoiPoint(id: 'q_plateau',     name: 'Plateau',             category: PoiCategory.quartier,  position: LatLng(14.6928, -17.4467)),
  PoiPoint(id: 'q_medina',      name: 'Médina',              category: PoiCategory.quartier,  position: LatLng(14.6901, -17.4530)),
  PoiPoint(id: 'q_grand_dakar', name: 'Grand Dakar',         category: PoiCategory.quartier,  position: LatLng(14.6792, -17.4508)),
  PoiPoint(id: 'q_hlm',         name: 'HLM',                 category: PoiCategory.quartier,  position: LatLng(14.6843, -17.4519)),
  PoiPoint(id: 'q_liberte',     name: 'Liberté',             category: PoiCategory.quartier,  position: LatLng(14.7052, -17.4579)),
  PoiPoint(id: 'q_sacre',       name: 'Sacré-Cœur',          category: PoiCategory.quartier,  position: LatLng(14.7109, -17.4689)),
  PoiPoint(id: 'q_almadies',    name: 'Almadies',            category: PoiCategory.quartier,  position: LatLng(14.7295, -17.5160)),
  PoiPoint(id: 'q_yoff',        name: 'Yoff',                category: PoiCategory.quartier,  position: LatLng(14.7495, -17.4830)),
  PoiPoint(id: 'q_ouakam',      name: 'Ouakam',              category: PoiCategory.quartier,  position: LatLng(14.7211, -17.4889)),
  PoiPoint(id: 'q_parcelles',   name: 'Parcelles Assainies', category: PoiCategory.quartier,  position: LatLng(14.7530, -17.4600)),
  PoiPoint(id: 'q_colobane',    name: 'Colobane',            category: PoiCategory.quartier,  position: LatLng(14.6866, -17.4591)),
  PoiPoint(id: 'q_ngor',        name: 'Ngor',                category: PoiCategory.quartier,  position: LatLng(14.7412, -17.5100)),
  PoiPoint(id: 'q_pointE',      name: 'Point E',             category: PoiCategory.quartier,  position: LatLng(14.6987, -17.4627)),
  PoiPoint(id: 'q_fann',        name: 'Fann',                category: PoiCategory.quartier,  position: LatLng(14.6948, -17.4554)),
  PoiPoint(id: 'q_mermoz',      name: 'Mermoz',              category: PoiCategory.quartier,  position: LatLng(14.7194, -17.4820)),

  // ── Hôpitaux ────────────────────────────────────────────────────────────────
  PoiPoint(id: 'h_principal',   name: 'Hôpital Principal',        category: PoiCategory.hopital, position: LatLng(14.6909, -17.4441)),
  PoiPoint(id: 'h_dantec',      name: 'Hôpital Aristide Le Dantec', category: PoiCategory.hopital, position: LatLng(14.6823, -17.4493)),
  PoiPoint(id: 'h_fann',        name: 'CHU Fann',                  category: PoiCategory.hopital, position: LatLng(14.6948, -17.4582)),
  PoiPoint(id: 'h_abass',       name: 'Hôpital Abass Ndao',        category: PoiCategory.hopital, position: LatLng(14.6922, -17.4533)),
  PoiPoint(id: 'h_grand',       name: 'Hôpital Grand Yoff',        category: PoiCategory.hopital, position: LatLng(14.7369, -17.4643)),
  PoiPoint(id: 'h_enfant',      name: 'Hôp. Albert Royer (Enfants)', category: PoiCategory.hopital, position: LatLng(14.6958, -17.4552)),

  // ── Marchés ─────────────────────────────────────────────────────────────────
  PoiPoint(id: 'm_sandaga',     name: 'Marché Sandaga',    category: PoiCategory.marche, position: LatLng(14.6917, -17.4411)),
  PoiPoint(id: 'm_kermel',      name: 'Marché Kermel',     category: PoiCategory.marche, position: LatLng(14.6877, -17.4430)),
  PoiPoint(id: 'm_tilene',      name: 'Marché Tilène',     category: PoiCategory.marche, position: LatLng(14.6876, -17.4549)),
  PoiPoint(id: 'm_colobane',    name: 'Marché Colobane',   category: PoiCategory.marche, position: LatLng(14.6871, -17.4594)),
  PoiPoint(id: 'm_hlm',         name: 'Marché HLM',        category: PoiCategory.marche, position: LatLng(14.6839, -17.4551)),
  PoiPoint(id: 'm_castors',     name: 'Marché des Castors', category: PoiCategory.marche, position: LatLng(14.7048, -17.4718)),
  PoiPoint(id: 'm_guediawaye',  name: 'Marché Guédiawaye',  category: PoiCategory.marche, position: LatLng(14.7710, -17.4060)),

  // ── Écoles / Universités ─────────────────────────────────────────────────────
  PoiPoint(id: 'e_ucad',        name: 'UCAD',              category: PoiCategory.ecole, position: LatLng(14.6928, -17.4573)),
  PoiPoint(id: 'e_ism',         name: 'ISM',               category: PoiCategory.ecole, position: LatLng(14.6984, -17.4625)),
  PoiPoint(id: 'e_esp',         name: 'École Polytechnique (ESP)', category: PoiCategory.ecole, position: LatLng(14.6910, -17.4575)),
  PoiPoint(id: 'e_uts',         name: 'Université du Sine Saloum', category: PoiCategory.ecole, position: LatLng(14.7005, -17.4610)),
  PoiPoint(id: 'e_cesi',        name: 'CESAG',             category: PoiCategory.ecole, position: LatLng(14.7145, -17.4671)),

  // ── Gares / Transports ───────────────────────────────────────────────────────
  PoiPoint(id: 'g_pompiers',    name: 'Gare des Pompiers',  category: PoiCategory.stationBus, position: LatLng(14.6909, -17.4374)),
  PoiPoint(id: 'g_ter_dakar',   name: 'Gare TER Dakar',     category: PoiCategory.stationBus, position: LatLng(14.6869, -17.4382)),
  PoiPoint(id: 'g_ter_colobane',name: 'Gare TER Colobane',  category: PoiCategory.stationBus, position: LatLng(14.6861, -17.4584)),
  PoiPoint(id: 'g_ter_thiaroye',name: 'Gare TER Thiaroye',  category: PoiCategory.stationBus, position: LatLng(14.7382, -17.3614)),
  PoiPoint(id: 'g_ddd_plateau', name: 'DDD Plateau',        category: PoiCategory.stationBus, position: LatLng(14.6918, -17.4465)),
  PoiPoint(id: 'g_ddd_almadies',name: 'DDD Almadies',       category: PoiCategory.stationBus, position: LatLng(14.7285, -17.5089)),

  // ── Stations Essence ─────────────────────────────────────────────────────────
  PoiPoint(id: 's_total_plateau', name: 'Total Plateau',    category: PoiCategory.stationEssence, position: LatLng(14.6935, -17.4445)),
  PoiPoint(id: 's_total_alm',    name: 'Total Almadies',    category: PoiCategory.stationEssence, position: LatLng(14.7228, -17.5019)),
  PoiPoint(id: 's_oryx_medina',  name: 'Oryx Médina',       category: PoiCategory.stationEssence, position: LatLng(14.6887, -17.4528)),
  PoiPoint(id: 's_shell_sacre',  name: 'Shell Sacré-Cœur',  category: PoiCategory.stationEssence, position: LatLng(14.7104, -17.4697)),
];

// ── Génère un label texte par POI (Map<poiId, BitmapDescriptor>) ─────────────
Future<Map<String, BitmapDescriptor>> buildPoiIcons() async {
  final icons = <String, BitmapDescriptor>{};
  for (final poi in dakarPois) {
    icons[poi.id] = await _buildPoiTextIcon(poi.name, poi.category);
  }
  return icons;
}

Future<BitmapDescriptor> _buildPoiTextIcon(String name, PoiCategory cat) async {
  const double fontSize  = 22.0;
  const double paddingH  = 12.0;
  const double paddingV  = 6.0;
  const double maxWidth  = 260.0;
  const double radius    = 10.0;

  // Mesure du texte
  final tp = TextPainter(
    text: TextSpan(
      text: name,
      style: TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);

  final imgW = (tp.width  + paddingH * 2).ceilToDouble();
  final imgH = (tp.height + paddingV * 2 + 3).ceilToDouble(); // +3 pour ombre

  final recorder = ui.PictureRecorder();
  final canvas   = Canvas(recorder);

  // Ombre portée
  final shadowRect = RRect.fromRectAndRadius(
    Rect.fromLTWH(1, 2, imgW - 2, imgH - 3),
    const Radius.circular(radius),
  );
  canvas.drawRRect(shadowRect, Paint()
    ..color = Colors.black.withValues(alpha: 0.28)
    ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3));

  // Fond coloré selon catégorie
  final bgRect = RRect.fromRectAndRadius(
    Rect.fromLTWH(0, 0, imgW - 2, imgH - 3),
    const Radius.circular(radius),
  );
  canvas.drawRRect(bgRect, Paint()..color = cat.color);

  // Bordure blanche fine
  canvas.drawRRect(bgRect, Paint()
    ..color = Colors.white.withValues(alpha: 0.40)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0);

  // Texte centré
  tp.paint(canvas, Offset(paddingH, paddingV));

  final picture = recorder.endRecording();
  final img     = await picture.toImage(imgW.toInt(), imgH.toInt());
  final bytes   = await img.toByteData(format: ui.ImageByteFormat.png);

  // Affichage à 50% de la taille de rendu → densité 2×
  return BitmapDescriptor.bytes(
    bytes!.buffer.asUint8List(),
    width:  imgW / 2,
    height: imgH / 2,
  );
}
