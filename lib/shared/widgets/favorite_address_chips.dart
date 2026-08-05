import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import 'pressable.dart';

/// Rangée horizontale de chips "adresses favorites" — sélection rapide
/// d'une adresse préenregistrée (Maison/Bureau/personnalisée) pour remplir
/// le champ d'adresse actif. Partagé entre "Livraison simple/Express" et
/// "Livraison groupée".
class FavoriteAddressChips extends StatelessWidget {
  final List<Map<String, dynamic>> favorites;
  final ValueChanged<Map<String, dynamic>> onSelect;
  const FavoriteAddressChips({
    super.key,
    required this.favorites,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (favorites.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: favorites.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final fav = favorites[i];
          return Pressable(
            onTap: () => onSelect(fav),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryMid],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppShadows.tinted(
                  AppColors.primary,
                  alpha: 0.35,
                  blur: 6,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fav['icon'] as String? ?? '📍',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    fav['label'] as String? ?? '',
                    style: ClientText.label.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
