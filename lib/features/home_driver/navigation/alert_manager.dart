import 'package:flutter/services.dart';

enum AlertPriority { low, medium, high }

class NavAlert {
  final String id;
  final String message;
  final AlertPriority priority;
  final double triggerDistance; // mètres

  const NavAlert({
    required this.id,
    required this.message,
    required this.priority,
    required this.triggerDistance,
  });
}

/// Gère les alertes contextuelles basées sur la distance à la cible.
/// Chaque alerte n'est déclenchée qu'une seule fois par phase.
class AlertManager {
  final _shown = <String>{};

  static const _pickupAlerts = [
    NavAlert(
      id: 'pickup_300',
      message: 'Point de collecte dans 300 m',
      priority: AlertPriority.low,
      triggerDistance: 300,
    ),
    NavAlert(
      id: 'pickup_100',
      message: 'Point de collecte dans 100 m',
      priority: AlertPriority.medium,
      triggerDistance: 100,
    ),
    NavAlert(
      id: 'pickup_30',
      message: 'Vous êtes arrivé au point de collecte',
      priority: AlertPriority.high,
      triggerDistance: 30,
    ),
  ];

  static const _deliveryAlerts = [
    NavAlert(
      id: 'delivery_300',
      message: 'Destination dans 300 m',
      priority: AlertPriority.low,
      triggerDistance: 300,
    ),
    NavAlert(
      id: 'delivery_100',
      message: 'Destination dans 100 m',
      priority: AlertPriority.medium,
      triggerDistance: 100,
    ),
    NavAlert(
      id: 'delivery_30',
      message: 'Vous êtes arrivé à destination',
      priority: AlertPriority.high,
      triggerDistance: 30,
    ),
  ];

  /// Vérifie si une nouvelle alerte doit être déclenchée.
  /// Retourne la plus spécifique (distance la plus courte) parmi les nouvelles.
  NavAlert? check(double distanceMeters, {required bool isPickupPhase}) {
    final alerts = isPickupPhase ? _pickupAlerts : _deliveryAlerts;
    NavAlert? toShow;

    // Parcours ordonné 300→100→30 : le dernier match est le plus précis
    for (final alert in alerts) {
      if (distanceMeters <= alert.triggerDistance && !_shown.contains(alert.id)) {
        _shown.add(alert.id);
        toShow = alert;
      }
    }

    if (toShow != null) _haptic(toShow.priority);
    return toShow;
  }

  void _haptic(AlertPriority priority) {
    switch (priority) {
      case AlertPriority.low:
        HapticFeedback.lightImpact();
      case AlertPriority.medium:
        HapticFeedback.mediumImpact();
      case AlertPriority.high:
        HapticFeedback.heavyImpact();
    }
  }
}
