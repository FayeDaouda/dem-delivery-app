import 'package:flutter/material.dart';

import 'alert_manager.dart';

/// Bannière d'alerte de proximité (300m/100m/arrivée), partagée entre l'écran
/// de course simple et l'écran de tournée batch.
class AlertBanner extends StatelessWidget {
  final String message;
  final AlertPriority priority;

  const AlertBanner({super.key, required this.message, required this.priority});

  Color get _color => switch (priority) {
        AlertPriority.low => Colors.blue.shade700,
        AlertPriority.medium => Colors.orange.shade700,
        AlertPriority.high => const Color(0xFF00C853),
      };

  IconData get _icon => switch (priority) {
        AlertPriority.low => Icons.info_outline,
        AlertPriority.medium => Icons.warning_amber_outlined,
        AlertPriority.high => Icons.check_circle,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(14),
        color: _color,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(_icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
