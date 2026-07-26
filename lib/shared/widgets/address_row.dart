import 'package:flutter/material.dart';

/// Ligne "icône + libellé + adresse", utilisée pour afficher un point de
/// collecte/livraison — partagée entre les écrans de notification et de
/// navigation livreur (fond clair ou sombre selon [dark]).
class AddressRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String? label;
  final String address;
  final bool dark;

  /// Variante dense sur une seule ligne (sans libellé, icône réduite) —
  /// utilisée dans les listes compactes (ex. cartes d'historique).
  final bool compact;

  const AddressRow({
    super.key,
    required this.icon,
    required this.iconColor,
    this.label,
    required this.address,
    this.dark = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = dark ? Colors.white60 : Colors.black45;
    final addressColor = dark ? Colors.white : Colors.black87;

    if (compact) {
      return Row(
        children: [
          Icon(icon, color: iconColor, size: 10),
          const SizedBox(width: 8),
          Expanded(
            child: Text(address,
                style: TextStyle(color: addressColor, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label != null)
                Text(label!,
                    style: TextStyle(
                        color: labelColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3)),
              Text(address,
                  style: TextStyle(
                      color: addressColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}
