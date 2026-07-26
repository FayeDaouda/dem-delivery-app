import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Anime l'apparition d'un point GPS sur la carte — chute + rebond du
/// marqueur jusqu'à sa position, puis un halo "sonar" à plusieurs anneaux qui
/// se propagent en cascade autour du point posé.
///
/// Le halo est rendu via des [Circle] Google Maps, ancrés en coordonnées
/// réelles (lat/lng + rayon en mètres) — pas en pixels écran. Contrairement à
/// un overlay Flutter positionné manuellement, il s'adapte donc tout seul au
/// zoom/pan de la caméra sans code de suivi supplémentaire : zoomer agrandit
/// son rendu à l'écran exactement comme n'importe quelle route ou marqueur.
///
/// Ne se déclenche qu'une fois par instance (`reveal()` est idempotent) —
/// un écran qui recrée sa position (nouvelle recherche GPS, changement
/// d'adresse) ne rejoue pas l'animation en boucle.
class LocationRevealController {
  LocationRevealController({required TickerProvider vsync, required VoidCallback onUpdate}) {
    _dropCtrl = AnimationController(vsync: vsync, duration: _dropDuration)
      ..addListener(onUpdate)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _haloCtrl.forward(from: 0);
      });
    _haloCtrl = AnimationController(vsync: vsync, duration: _haloDuration)..addListener(onUpdate);
  }

  late final AnimationController _dropCtrl;
  late final AnimationController _haloCtrl;

  static const _dropDuration = Duration(milliseconds: 700);
  static const _haloDuration = Duration(milliseconds: 2100);

  static const int ringCount = 3;
  static const double _ringStagger = 0.22; // décalage entre anneaux (fraction du cycle)
  static const double _ringLife = 0.5;     // durée de vie d'un anneau (fraction du cycle)

  /// Rayon maximal atteint par un anneau, en mètres — volontairement large
  /// pour bien se voir même dézoomé sur un quartier entier.
  static const double maxRadiusMeters = 250;

  static const double _dropOffsetLat = 0.006; // ~650 m au nord — "au-dessus" à l'écran

  bool _revealed = false;

  /// [withDrop] anime aussi la chute du marqueur (via [markerPosition]) —
  /// à désactiver pour un point qui se déplace déjà en continu (position GPS
  /// live d'un utilisateur), où une chute depuis une fausse position n'aurait
  /// pas de sens.
  void reveal({bool withDrop = true}) {
    if (_revealed) return;
    _revealed = true;
    if (withDrop) {
      _dropCtrl.forward(from: 0);
    } else {
      _haloCtrl.forward(from: 0);
    }
  }

  /// Position interpolée du marqueur pendant la chute — renvoie [target]
  /// directement une fois l'animation terminée (ou si elle n'a pas démarré).
  LatLng markerPosition(LatLng target) {
    if (_dropCtrl.value >= 1.0) return target;
    final start = LatLng(target.latitude + _dropOffsetLat, target.longitude);
    final t = Curves.bounceOut.transform(_dropCtrl.value);
    return LatLng(
      start.latitude + (target.latitude - start.latitude) * t,
      start.longitude + (target.longitude - start.longitude) * t,
    );
  }

  /// Anneaux du halo à l'instant courant — vide en dehors de la fenêtre
  /// d'animation. [center] doit suivre la position réelle du point (pas la
  /// position interpolée de la chute) pour rester cohérent une fois posé.
  Set<Circle> haloCircles(LatLng center, {required Color color, String idPrefix = 'halo'}) {
    if (!_haloCtrl.isAnimating) return {};
    final circles = <Circle>{};
    for (var i = 0; i < ringCount; i++) {
      final start = i * _ringStagger;
      if (_haloCtrl.value < start) continue;
      final local = ((_haloCtrl.value - start) / _ringLife).clamp(0.0, 1.0);
      if (local >= 1.0) continue;
      final eased = Curves.easeOut.transform(local);
      final alpha = 1 - eased;
      circles.add(Circle(
        circleId: CircleId('$idPrefix-$i'),
        center: center,
        radius: 15 + eased * maxRadiusMeters,
        fillColor: color.withValues(alpha: alpha * 0.10),
        strokeColor: color.withValues(alpha: alpha * 0.55),
        strokeWidth: 2,
      ));
    }
    return circles;
  }

  void dispose() {
    _dropCtrl.dispose();
    _haloCtrl.dispose();
  }
}
