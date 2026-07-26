import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Résultat d'un recalage position ↔ tracé : le segment le plus proche, le
/// point projeté dessus, et la distance réelle jusqu'à ce point.
class RouteProjection {
  final int segmentIndex;
  final LatLng projected;
  final double distanceMeters;

  const RouteProjection({
    required this.segmentIndex,
    required this.projected,
    required this.distanceMeters,
  });
}

/// "Map matching" simple : recale une position GPS sur le tracé affiché.
///
/// Remplace l'ancienne logique qui cherchait le *sommet* du polyline le plus
/// proche dans une fenêtre bornée (60-80 points) — deux défauts que ça
/// provoquait : le tracé ne se raccourcissait que par sauts d'un sommet à
/// l'autre (jamais en continu jusqu'à la position réelle du livreur), et la
/// détection de déviation ratait les cas où le point réellement le plus
/// proche sortait de la fenêtre bornée.
///
/// Ici on projette orthogonalement la position sur chaque *segment* (pas
/// seulement les sommets), sans limite de fenêtre — seulement une borne
/// inférieure (`fromIndex`, le tracé ne recule jamais). Un parcours complet
/// du tracé restant à chaque position GPS reste trivial (quelques centaines
/// de points, au plus 1-2 fois/seconde en usage réel).
class RouteTracker {
  const RouteTracker._();

  static RouteProjection? closestMatch(List<LatLng> route, LatLng driver, int fromIndex) {
    if (route.length < 2) return null;
    final start = fromIndex.clamp(0, route.length - 2);

    int bestIdx = start;
    LatLng bestPoint = route[start];
    double bestDist = double.infinity;

    for (int i = start; i < route.length - 1; i++) {
      final proj = _projectOnSegment(driver, route[i], route[i + 1]);
      final dist = Geolocator.distanceBetween(
        driver.latitude, driver.longitude,
        proj.latitude, proj.longitude,
      );
      if (dist < bestDist) {
        bestDist = dist;
        bestIdx = i;
        bestPoint = proj;
      }
    }

    return RouteProjection(segmentIndex: bestIdx, projected: bestPoint, distanceMeters: bestDist);
  }

  /// Portion de tracé à afficher : la position projetée du livreur (donc le
  /// trait démarre pile sur sa position live), puis les sommets restants.
  static List<LatLng> remainingRoute(List<LatLng> route, RouteProjection match) {
    return [match.projected, ...route.sublist(match.segmentIndex + 1)];
  }

  /// Projection orthogonale de [p] sur le segment [a]-[b], en repère local
  /// équirectangulaire (approximation standard et suffisamment précise à
  /// l'échelle d'une rue/route — les mêmes hypothèses que la plupart des
  /// moteurs de map matching légers).
  static LatLng _projectOnSegment(LatLng p, LatLng a, LatLng b) {
    final latRef = a.latitude * pi / 180;
    const mPerDegLat = 111320.0;
    final mPerDegLng = 111320.0 * cos(latRef);

    final bx = (b.longitude - a.longitude) * mPerDegLng;
    final by = (b.latitude - a.latitude) * mPerDegLat;
    final px = (p.longitude - a.longitude) * mPerDegLng;
    final py = (p.latitude - a.latitude) * mPerDegLat;

    final lenSq = bx * bx + by * by;
    final t = lenSq == 0 ? 0.0 : ((px * bx + py * by) / lenSq).clamp(0.0, 1.0);

    final projX = t * bx;
    final projY = t * by;

    return LatLng(
      a.latitude + projY / mPerDegLat,
      a.longitude + projX / mPerDegLng,
    );
  }
}
