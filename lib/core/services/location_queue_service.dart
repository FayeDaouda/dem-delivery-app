import '../../features/deliveries/data/orders_repository.dart';

/// File d'attente légère pour l'émission de position GPS pendant une course.
///
/// `OrdersRepository.updateDriverLocation` échouait auparavant en silence
/// (coupure réseau = position perdue, sans retry). Ici, la dernière position
/// connue est conservée si l'envoi échoue et sera retentée au prochain appel
/// — pas de retry actif/timer : le flux GPS applique déjà un tick régulier
/// (~10s), qui sert naturellement de nouvelle tentative.
class LocationQueueService {
  LocationQueueService(this._repo);
  final OrdersRepository _repo;

  double? _pendingLat;
  double? _pendingLng;
  bool _sending = false;

  Future<void> emit(double lat, double lng) async {
    _pendingLat = lat;
    _pendingLng = lng;
    // Un envoi est déjà en cours : il reprendra la position la plus récente
    // dès qu'il se libère, pas besoin d'en démarrer un second en parallèle.
    if (_sending) return;

    _sending = true;
    try {
      while (_pendingLat != null && _pendingLng != null) {
        final sendLat = _pendingLat!;
        final sendLng = _pendingLng!;
        try {
          await _repo.updateDriverLocation(sendLat, sendLng);
          // Vide la file seulement si aucune position plus récente n'est
          // arrivée pendant l'envoi.
          if (_pendingLat == sendLat && _pendingLng == sendLng) {
            _pendingLat = null;
            _pendingLng = null;
          }
        } catch (_) {
          // Échec réseau — on garde la position en attente ; le prochain
          // tick GPS déclenchera un nouvel essai avec la position la plus
          // récente disponible à ce moment-là.
          break;
        }
      }
    } finally {
      _sending = false;
    }
  }
}
