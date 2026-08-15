import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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

// ── Sélecteur "Adresses préenregistrées" ──────────────────────────────────
// Ouvert depuis le menu d'adresse (voir address_options_sheet.dart, choix
// `AddressOptionChoice.favorites`). Avant, ce choix se contentait de fermer
// le menu et de positionner un flag interne — sans aucune liste ni message,
// ça ne faisait RIEN de visible pour un utilisateur sans adresse enregistrée
// (le cas le plus courant). Ce sélecteur remplace ce silence par une vraie
// liste tap-to-select, ou un état vide explicite avec accès direct à la
// gestion des adresses.
Future<Map<String, dynamic>?> pickFavoriteAddress(
  BuildContext context, {
  required List<Map<String, dynamic>> favorites,
  required bool forPickup,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        _FavoriteAddressPickerSheet(favorites: favorites, forPickup: forPickup),
  );
}

class _FavoriteAddressPickerSheet extends StatelessWidget {
  final List<Map<String, dynamic>> favorites;
  final bool forPickup;
  const _FavoriteAddressPickerSheet({
    required this.favorites,
    required this.forPickup,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
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
          const SizedBox(height: 4),
          Text(
            'Vos adresses enregistrées',
            style: ClientText.caption.copyWith(
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 16),
          if (favorites.isEmpty)
            _EmptyFavorites(
              onManage: () {
                Navigator.pop(context);
                context.push('/client/favorite-addresses');
              },
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: favorites.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final fav = favorites[i];
                  return Pressable(
                    onTap: () => Navigator.pop(context, fav),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            fav['icon'] as String? ?? '📍',
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fav['label'] as String? ?? '',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  fav['address'] as String? ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.65),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: Colors.white.withValues(alpha: 0.5),
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyFavorites extends StatelessWidget {
  final VoidCallback onManage;
  const _EmptyFavorites({required this.onManage});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 28),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(
                Icons.star_outline_rounded,
                color: Colors.white.withValues(alpha: 0.5),
                size: 32,
              ),
              const SizedBox(height: 10),
              Text(
                'Aucune adresse enregistrée',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Enregistrez votre domicile ou bureau pour les retrouver ici la prochaine fois.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.60),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Pressable(
          onTap: onManage,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                'Ajouter une adresse',
                style: TextStyle(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
