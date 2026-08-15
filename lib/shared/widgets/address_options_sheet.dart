import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import 'pressable.dart';

enum AddressOptionChoice { currentLocation, favorites, map, manual }

/// Menu ouvert au tap sur une bulle d'adresse (départ/destination) :
/// position actuelle, adresses favorites, pointer sur la carte, ou écrire
/// l'adresse — un seul point d'entrée pour renseigner l'adresse plutôt que
/// des affordances éparpillées (bouton GPS, icône carte, saisie directe).
Future<AddressOptionChoice?> showAddressOptionsSheet(
  BuildContext context, {
  required bool forPickup,
  // Masqué tant que l'écran appelant n'a pas de mode "pointer sur la
  // carte" implémenté (ex: Livraison groupée, pas encore construit) — un
  // choix menant à une fonctionnalité absente serait pire que son absence.
  bool showMapOption = true,
}) {
  return showModalBottomSheet<AddressOptionChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _AddressOptionsSheet(
      forPickup: forPickup,
      showMapOption: showMapOption,
    ),
  );
}

class _AddressOptionsSheet extends StatelessWidget {
  final bool forPickup;
  final bool showMapOption;
  const _AddressOptionsSheet({
    required this.forPickup,
    required this.showMapOption,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        // Dégradé cyan (comme DEM Pro) au lieu d'un bleu marine uni.
        gradient: AppColors.gradientSplash,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewPadding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            forPickup ? 'Adresse de départ' : 'Adresse de destination',
            style: ClientText.subtitle.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          _OptionRow(
            icon: Icons.my_location,
            label: 'Ma position actuelle',
            onTap: () =>
                Navigator.pop(context, AddressOptionChoice.currentLocation),
          ),
          _OptionRow(
            icon: Icons.star_outline_rounded,
            label: 'Adresses préenregistrées',
            onTap: () => Navigator.pop(context, AddressOptionChoice.favorites),
          ),
          if (showMapOption)
            _OptionRow(
              icon: Icons.map_outlined,
              label: 'Pointer sur la carte',
              onTap: () => Navigator.pop(context, AddressOptionChoice.map),
            ),
          _OptionRow(
            icon: Icons.edit_outlined,
            label: "Écrire l'adresse",
            onTap: () => Navigator.pop(context, AddressOptionChoice.manual),
          ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _OptionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Text(label, style: ClientText.body.copyWith(color: Colors.white)),
        ],
      ),
    ),
  );
}
