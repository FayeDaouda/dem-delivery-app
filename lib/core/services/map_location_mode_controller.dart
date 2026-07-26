import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';

enum MapLocationMode { free, follow, compass }

/// Gère le cycle "libre → suivi → boussole" partagé par tous les écrans avec
/// carte live (accueil client, suivi de commande...) : quel mode est actif,
/// et l'abonnement au capteur magnétomètre pour le mode boussole.
///
/// Ce contrôleur ne décide PAS ce que la caméra doit centrer (position du
/// client, du livreur suivi...) — ça reste propre à chaque écran, qui fournit
/// [onUpdate] pour recalculer sa caméra à chaque changement de mode ou de cap.
class MapLocationModeController {
  MapLocationModeController({
    this.mode = MapLocationMode.follow,
    required this.onUpdate,
  });

  MapLocationMode mode;
  double compassBearing = 0;
  StreamSubscription<CompassEvent>? _compassSub;

  /// Appelé après chaque changement de mode ou de cap boussole — l'écran
  /// hôte y met à jour sa caméra et rebuild (ex. via `setState`).
  final VoidCallback onUpdate;

  bool get isFree => mode == MapLocationMode.free;
  bool get isFollow => mode == MapLocationMode.follow;
  bool get isCompass => mode == MapLocationMode.compass;

  /// Cycle libre → suivi → boussole → libre.
  void cycle() {
    switch (mode) {
      case MapLocationMode.free:
        mode = MapLocationMode.follow;
        _stopCompass();
      case MapLocationMode.follow:
        mode = MapLocationMode.compass;
        _startCompass();
      case MapLocationMode.compass:
        mode = MapLocationMode.free;
        _stopCompass();
    }
    onUpdate();
  }

  /// L'utilisateur a déplacé la carte manuellement (drag) — repasse en mode
  /// libre, comme sur les cartes Uber/Google Maps. À appeler depuis
  /// `onCameraMove`, en ignorant les déplacements programmatiques de l'écran.
  void notifyManualPan() {
    if (mode == MapLocationMode.free) return;
    _stopCompass();
    mode = MapLocationMode.free;
    onUpdate();
  }

  void _startCompass() {
    _compassSub ??= FlutterCompass.events?.listen(_onCompassEvent);
  }

  void _stopCompass() {
    _compassSub?.cancel();
    _compassSub = null;
  }

  void _onCompassEvent(CompassEvent event) {
    final heading = event.heading;
    if (heading == null || mode != MapLocationMode.compass) return;
    // Filtre : ignore les changements < 2° pour éviter le tremblement.
    if ((compassBearing - heading).abs() < 2.0) return;
    compassBearing = heading;
    onUpdate();
  }

  void dispose() => _stopCompass();
}
