import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Décrit la promo mise en avant côté serveur (voir
/// promo.service.js:getHighlightPromo) — pas de montant exact calculé
/// (aucun prix connu à ce stade), juste de quoi afficher un teaser.
String _describeHighlight(Map<String, dynamic> promo) {
  final type = promo['type'] as String?;
  final value = (promo['value'] as num?)?.toDouble();
  final minOrderPrice = (promo['minOrderPrice'] as num?)?.toInt();
  final suffix = minOrderPrice != null
      ? '\nDès $minOrderPrice FCFA de commande.'
      : '';
  switch (type) {
    case 'FREE_COURSE':
      return 'Votre prochaine livraison éligible est gratuite !$suffix';
    case 'PERCENT_OFF':
      return '-${value?.toStringAsFixed(0)}% sur votre prochaine livraison éligible.$suffix';
    case 'FIXED_OFF':
      return '-${value?.toStringAsFixed(0)} FCFA sur votre prochaine livraison éligible.$suffix';
    default:
      return 'Une réduction est disponible sur votre prochaine livraison.$suffix';
  }
}

/// Se souvient de la dernière promo déjà montrée (par nom de campagne) pour
/// ne pas rouvrir la même popup à chaque ouverture de l'app — seule une
/// NOUVELLE campagne (nom différent) redéclenche l'affichage.
class _PromoHighlightSeen {
  static const _key = 'last_seen_highlight_promo';

  static Future<bool> alreadySeen(String name) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) == name;
  }

  static Future<void> markSeen(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, name);
  }
}

/// Vérifie s'il existe une promo à mettre en avant et l'affiche en popup si
/// elle n'a pas déjà été vue — à appeler une fois après le premier frame de
/// l'écran d'accueil (client ou DEM Pro). [fetch] fait l'appel réseau
/// (silencieux, jamais bloquant si indisponible) ; [accentColor] permet
/// d'adapter la popup au thème de l'app appelante.
Future<void> maybeShowPromoHighlight(
  BuildContext context, {
  required Future<Map<String, dynamic>?> Function() fetch,
  Color accentColor = const Color(0xFF0077B6),
}) async {
  final promo = await fetch();
  if (promo == null) return;
  final name = promo['name'] as String? ?? '';
  if (name.isEmpty || await _PromoHighlightSeen.alreadySeen(name)) return;
  await _PromoHighlightSeen.markSeen(name);
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [accentColor, accentColor.withValues(alpha: 0.7)],
                ),
              ),
              child: const Icon(
                Icons.local_offer_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _describeHighlight(promo),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: Color(0xFF6B7280),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Super !',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
