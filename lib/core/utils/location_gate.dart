import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

Future<bool> ensureLocationEnabled(BuildContext context) async {
  var permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.deniedForever) {
    if (!context.mounted) return false;
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.location_off, color: Color(0xFFEF4444), size: 22),
          SizedBox(width: 8),
          Text('Localisation désactivée', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        content: const Text(
          'La localisation est bloquée pour DEM. Allez dans les réglages de votre téléphone pour l\'autoriser.',
          style: TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ouvrir les réglages', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (openSettings == true) await Geolocator.openAppSettings();
    return false;
  }

  if (permission == LocationPermission.denied) {
    if (!context.mounted) return false;
    final ask = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.location_on, color: Color(0xFF0CB8DE), size: 22),
          SizedBox(width: 8),
          Expanded(child: Text('Activez la localisation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
        ]),
        content: const Text(
          'DEM a besoin de votre position pour calculer le trajet et vous connecter au livreur le plus proche.',
          style: TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Plus tard', style: TextStyle(color: Color(0xFF6B7280))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Activer', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ask != true) return false;
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return false;
    }
  }

  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    if (!context.mounted) return false;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.gps_off, color: Color(0xFFF59E0B), size: 22),
          SizedBox(width: 8),
          Text('GPS désactivé', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        content: const Text(
          'Activez le GPS de votre téléphone pour utiliser DEM.',
          style: TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Compris', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    await Geolocator.openLocationSettings();
    return false;
  }

  return true;
}
