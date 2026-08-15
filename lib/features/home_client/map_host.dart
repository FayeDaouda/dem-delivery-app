import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Petite interface exposée par ClientHomeShellScreen à chaque contrôleur de
/// mode (OrderWizardController, BatchWizardController) — leur donne accès à
/// la carte/caméra partagée sans qu'ils aient besoin de connaître le socle
/// (GoogleMapController, position GPS, mécanisme de mesure de la feuille).
abstract class MapHost {
  GoogleMapController? get mapController;

  /// Dernière position GPS connue du socle — peut être null tant que le
  /// premier relevé n'est pas encore arrivé.
  LatLng? get currentPosition;

  /// Centre courant de la caméra (mode "pointer sur la carte" — lu au
  /// moment de la confirmation) et indicateur de pan/zoom en cours (pour un
  /// simple effet visuel de pulsation sur l'épingle centrale).
  LatLng get currentCameraPosition;
  bool get isMapMoving;

  /// Centre la caméra sur [pos], décalée vers le sud pour rester visible
  /// au-dessus du panneau (voir _estimatedPanelHeight côté socle).
  void centerOn(LatLng pos, {double zoom = 14, double tilt = 30});

  /// Cadre tous les [points] pour qu'ils restent visibles au-dessus du
  /// panneau (bornes ajustées, zoom automatique).
  void fitPoints(List<LatLng> points);

  /// Force une nouvelle mesure de la hauteur du panneau — à appeler après un
  /// changement de mode/étape dont le contenu diffère nettement en hauteur.
  void requestSheetRemeasure();
}
