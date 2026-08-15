/// Formate un nombre de secondes en durée courte ("2h30", "45min", "0min") —
/// utilisé pour le temps disponible aujourd'hui d'un livreur (dashboard,
/// détail livreur), calculé côté serveur depuis DriverAvailabilityLog.
String formatActiveDuration(int seconds) {
  final totalMinutes = seconds ~/ 60;
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  if (h == 0) return '${m}min';
  if (m == 0) return '${h}h';
  return '${h}h${m.toString().padLeft(2, '0')}';
}
