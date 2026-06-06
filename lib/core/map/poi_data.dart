import 'dart:math';
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
      case PoiCategory.quartier:       return 'Quartier';
      case PoiCategory.hopital:        return 'Hôpital';
      case PoiCategory.marche:         return 'Marché';
      case PoiCategory.ecole:          return 'École / Université';
      case PoiCategory.stationBus:     return 'Gare / Transport';
      case PoiCategory.stationEssence: return 'Station essence';
    }
  }

  Color get color {
    switch (this) {
      case PoiCategory.quartier:       return const Color(0xFF37474F); // bleu-ardoise sobre
      case PoiCategory.hopital:        return const Color(0xFF04317C); // bleu marine (brand)
      case PoiCategory.marche:         return const Color(0xFF0D47A1); // bleu foncé
      case PoiCategory.ecole:          return const Color(0xFF1565C0); // bleu moyen
      case PoiCategory.stationBus:     return const Color(0xFF01579B); // bleu cobalt
      case PoiCategory.stationEssence: return const Color(0xFF283593); // bleu indigo
    }
  }

  // Priorité d'affichage (plus haute = visible en premier / résiste à la collision)
  int get priority {
    switch (this) {
      case PoiCategory.hopital:        return 4;
      case PoiCategory.marche:         return 3;
      case PoiCategory.ecole:          return 3;
      case PoiCategory.stationBus:     return 3;
      case PoiCategory.stationEssence: return 2;
      case PoiCategory.quartier:       return 1;
    }
  }

  // Zoom minimum pour l'affichage progressif
  double get minZoom {
    switch (this) {
      case PoiCategory.quartier:       return 13.0;
      case PoiCategory.hopital:        return 13.0;
      case PoiCategory.marche:         return 14.0;
      case PoiCategory.ecole:          return 14.0;
      case PoiCategory.stationBus:     return 14.0;
      case PoiCategory.stationEssence: return 15.0;
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

// ── Jeu d'icônes 3 tailles (small / medium / large) ──────────────────────────
class PoiIconSet {
  final Map<String, BitmapDescriptor> small;
  final Map<String, BitmapDescriptor> medium;
  final Map<String, BitmapDescriptor> large;

  const PoiIconSet({
    required this.small,
    required this.medium,
    required this.large,
  });

  Map<String, BitmapDescriptor> iconsForZoom(double zoom) {
    if (zoom >= 15.5) return large;
    if (zoom >= 14.0) return medium;
    return small;
  }
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
  PoiPoint(id: 'h_principal',   name: 'Hôpital Principal',          category: PoiCategory.hopital, position: LatLng(14.6909, -17.4441)),
  PoiPoint(id: 'h_dantec',      name: 'Hôpital Le Dantec',          category: PoiCategory.hopital, position: LatLng(14.6823, -17.4493)),
  PoiPoint(id: 'h_fann',        name: 'CHU Fann',                   category: PoiCategory.hopital, position: LatLng(14.6948, -17.4582)),
  PoiPoint(id: 'h_abass',       name: 'Hôpital Abass Ndao',         category: PoiCategory.hopital, position: LatLng(14.6922, -17.4533)),
  PoiPoint(id: 'h_grand',       name: 'Hôpital Grand Yoff',         category: PoiCategory.hopital, position: LatLng(14.7369, -17.4643)),
  PoiPoint(id: 'h_enfant',      name: 'Hôp. Albert Royer',          category: PoiCategory.hopital, position: LatLng(14.6958, -17.4552)),

  // ── Marchés ─────────────────────────────────────────────────────────────────
  PoiPoint(id: 'm_sandaga',     name: 'Marché Sandaga',     category: PoiCategory.marche, position: LatLng(14.6917, -17.4411)),
  PoiPoint(id: 'm_kermel',      name: 'Marché Kermel',      category: PoiCategory.marche, position: LatLng(14.6877, -17.4430)),
  PoiPoint(id: 'm_tilene',      name: 'Marché Tilène',      category: PoiCategory.marche, position: LatLng(14.6876, -17.4549)),
  PoiPoint(id: 'm_colobane',    name: 'Marché Colobane',    category: PoiCategory.marche, position: LatLng(14.6871, -17.4594)),
  PoiPoint(id: 'm_hlm',         name: 'Marché HLM',         category: PoiCategory.marche, position: LatLng(14.6839, -17.4551)),
  PoiPoint(id: 'm_castors',     name: 'Marché des Castors', category: PoiCategory.marche, position: LatLng(14.7048, -17.4718)),
  PoiPoint(id: 'm_guediawaye',  name: 'Marché Guédiawaye',  category: PoiCategory.marche, position: LatLng(14.7710, -17.4060)),

  // ── Écoles / Universités ─────────────────────────────────────────────────────
  PoiPoint(id: 'e_ucad',        name: 'UCAD',                        category: PoiCategory.ecole, position: LatLng(14.6928, -17.4573)),
  PoiPoint(id: 'e_ism',         name: 'ISM',                         category: PoiCategory.ecole, position: LatLng(14.6984, -17.4625)),
  PoiPoint(id: 'e_esp',         name: 'École Polytechnique',         category: PoiCategory.ecole, position: LatLng(14.6910, -17.4575)),
  PoiPoint(id: 'e_uts',         name: 'Univ. Sine Saloum',           category: PoiCategory.ecole, position: LatLng(14.7005, -17.4610)),
  PoiPoint(id: 'e_cesi',        name: 'CESAG',                       category: PoiCategory.ecole, position: LatLng(14.7145, -17.4671)),

  // ── Gares / Transports ───────────────────────────────────────────────────────
  PoiPoint(id: 'g_pompiers',     name: 'Gare des Pompiers',  category: PoiCategory.stationBus, position: LatLng(14.6909, -17.4374)),
  PoiPoint(id: 'g_ter_dakar',    name: 'Gare TER Dakar',     category: PoiCategory.stationBus, position: LatLng(14.6869, -17.4382)),
  PoiPoint(id: 'g_ter_colobane', name: 'Gare TER Colobane',  category: PoiCategory.stationBus, position: LatLng(14.6861, -17.4584)),
  PoiPoint(id: 'g_ter_thiaroye', name: 'Gare TER Thiaroye',  category: PoiCategory.stationBus, position: LatLng(14.7382, -17.3614)),
  PoiPoint(id: 'g_ddd_plateau',  name: 'DDD Plateau',        category: PoiCategory.stationBus, position: LatLng(14.6918, -17.4465)),
  PoiPoint(id: 'g_ddd_almadies', name: 'DDD Almadies',       category: PoiCategory.stationBus, position: LatLng(14.7285, -17.5089)),

  // ── Stations Essence ─────────────────────────────────────────────────────────
  PoiPoint(id: 's_total_plateau', name: 'Total Plateau',   category: PoiCategory.stationEssence, position: LatLng(14.6935, -17.4445)),
  PoiPoint(id: 's_total_alm',     name: 'Total Almadies',  category: PoiCategory.stationEssence, position: LatLng(14.7228, -17.5019)),
  PoiPoint(id: 's_oryx_medina',   name: 'Oryx Médina',     category: PoiCategory.stationEssence, position: LatLng(14.6887, -17.4528)),
  PoiPoint(id: 's_shell_sacre',   name: 'Shell Sacré-Cœur', category: PoiCategory.stationEssence, position: LatLng(14.7104, -17.4697)),
];

// ── Construit les 3 tailles d'icônes ─────────────────────────────────────────
Future<PoiIconSet> buildPoiIconSet(List<PoiPoint> pois) async {
  final small  = <String, BitmapDescriptor>{};
  final medium = <String, BitmapDescriptor>{};
  final large  = <String, BitmapDescriptor>{};
  for (final poi in pois) {
    small[poi.id]  = await _buildPoiTextIcon(poi.name, poi.category, 13.0);
    medium[poi.id] = await _buildPoiTextIcon(poi.name, poi.category, 17.0);
    large[poi.id]  = await _buildPoiTextIcon(poi.name, poi.category, 21.0);
  }
  return PoiIconSet(small: small, medium: medium, large: large);
}

// ── Construit les markers selon zoom (filtre progressif + collision) ──────────
Set<Marker> buildPoiMarkersForZoom(
    PoiIconSet iconSet, double zoom, List<PoiPoint> pois) {
  if (zoom < 13.0) return {};

  final icons = iconSet.iconsForZoom(zoom);

  // Filtre par zoom minimum de la catégorie
  final visible = pois.where((p) => zoom >= p.category.minZoom).toList();

  // Tri priorité décroissante → les plus importants passent en premier
  visible.sort((a, b) => b.category.priority.compareTo(a.category.priority));

  // Collision detection géographique : distance minimale selon zoom
  final minDist  = _minDistMetersForZoom(zoom);
  final accepted = <PoiPoint>[];

  for (final poi in visible) {
    if (minDist > 0 &&
        accepted.any((a) => _haversineMeters(poi.position, a.position) < minDist)) {
      continue;
    }
    accepted.add(poi);
  }

  return accepted.map((poi) {
    final icon = icons[poi.id];
    if (icon == null) return null;
    return Marker(
      markerId: MarkerId('poi_${poi.id}'),
      position: poi.position,
      icon: icon,
      anchor: const Offset(0.5, 0.5),
      zIndexInt: 1,
      infoWindow: InfoWindow(title: poi.name, snippet: poi.category.label),
    );
  }).whereType<Marker>().toSet();
}

// ── Distance minimale entre labels selon zoom (évite le chevauchement) ────────
double _minDistMetersForZoom(double zoom) {
  if (zoom >= 15.5) return 0;
  if (zoom >= 15.0) return 150;
  if (zoom >= 14.0) return 500;
  return 1500;
}

// ── Distance orthodromique (Haversine) en mètres ─────────────────────────────
double _haversineMeters(LatLng a, LatLng b) {
  const R = 6371000.0;
  final lat1 = a.latitude  * pi / 180;
  final lat2 = b.latitude  * pi / 180;
  final dLat = (b.latitude  - a.latitude)  * pi / 180;
  final dLon = (b.longitude - a.longitude) * pi / 180;
  final sin2 = sin(dLat / 2) * sin(dLat / 2) +
               cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
  return R * 2 * atan2(sqrt(sin2), sqrt(1 - sin2));
}

// ── Rendu texte : halo blanc + texte coloré, sans fond ───────────────────────
Future<BitmapDescriptor> _buildPoiTextIcon(
    String name, PoiCategory cat, double fontSize) async {
  const double maxWidth   = 220.0;
  const double haloSpace  = 2.5; // marge autour du texte pour le halo

  // Mesure le texte (sans couleur : juste pour les dimensions)
  final measureTp = TextPainter(
    text: TextSpan(
      text: name,
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);

  final imgW = (measureTp.width  + haloSpace * 2 + 2).ceilToDouble();
  final imgH = (measureTp.height + haloSpace * 2 + 1).ceilToDouble();

  final recorder = ui.PictureRecorder();
  final canvas   = Canvas(recorder);

  // Passe 1 : halo blanc (stroke)
  final haloTp = TextPainter(
    text: TextSpan(
      text: name,
      style: TextStyle(
        fontSize:   fontSize,
        fontWeight: FontWeight.w800,
        foreground: Paint()
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..strokeJoin  = StrokeJoin.round
          ..color       = Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);

  haloTp.paint(canvas, Offset(haloSpace, haloSpace));

  // Passe 2 : texte coloré par catégorie
  final textTp = TextPainter(
    text: TextSpan(
      text: name,
      style: TextStyle(
        fontSize:   fontSize,
        fontWeight: FontWeight.w800,
        color:      cat.color,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);

  textTp.paint(canvas, Offset(haloSpace, haloSpace));

  final picture = recorder.endRecording();
  final img     = await picture.toImage(imgW.toInt(), imgH.toInt());
  final bytes   = await img.toByteData(format: ui.ImageByteFormat.png);

  // Rendu à 50% → densité 2× implicite
  return BitmapDescriptor.bytes(
    bytes!.buffer.asUint8List(),
    width:  imgW / 2,
    height: imgH / 2,
  );
}
