import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Décrit la promo mise en avant côté serveur (voir
/// promo.service.js:getHighlightPromo) — pas de montant exact calculé
/// (aucun prix connu à ce stade), en langage simple (pas de jargon "éligible").
String _describeHighlight(Map<String, dynamic> promo) {
  final type = promo['type'] as String?;
  final value = (promo['value'] as num?)?.toDouble();
  final minOrderPrice = (promo['minOrderPrice'] as num?)?.toInt();
  final suffix = minOrderPrice != null
      ? '\nDès $minOrderPrice FCFA de commande.'
      : '';
  switch (type) {
    case 'FREE_COURSE':
      return 'Votre prochaine commande est offerte !$suffix';
    case 'PERCENT_OFF':
      return '-${value?.toStringAsFixed(0)}% sur votre prochaine commande.$suffix';
    case 'FIXED_OFF':
      return '-${value?.toStringAsFixed(0)} FCFA sur votre prochaine commande.$suffix';
    default:
      return 'Une réduction est disponible sur votre prochaine commande.$suffix';
  }
}

/// Texte court sur la date limite, si la campagne en a une — `null` si pas
/// de deadline (rien à afficher dans ce cas).
String? _describeDeadline(Map<String, dynamic> promo) {
  final raw = promo['expiresAt'] as String?;
  if (raw == null) return null;
  final expiresAt = DateTime.tryParse(raw)?.toLocal();
  if (expiresAt == null) return null;
  final days = expiresAt.difference(DateTime.now()).inHours / 24;
  final datePart =
      '${expiresAt.day.toString().padLeft(2, '0')}/${expiresAt.month.toString().padLeft(2, '0')}';
  if (days <= 0) return 'Se termine aujourd\'hui !';
  if (days < 1) return 'Se termine ce soir !';
  final d = days.ceil();
  if (d == 1) return 'Encore 1 jour — jusqu\'au $datePart';
  if (d <= 7) return 'Encore $d jours — jusqu\'au $datePart';
  return 'Valable jusqu\'au $datePart';
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

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Promotion',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (ctx, anim, secondaryAnim) =>
        _PromoHighlightDialog(promo: promo, accentColor: accentColor),
    transitionBuilder: (ctx, anim, _, child) {
      final scale = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      );
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: anim,
          curve: Curves.easeOut,
          reverseCurve: Curves.easeIn,
        ),
        child: ScaleTransition(scale: scale, child: child),
      );
    },
  );
}

class _PromoHighlightDialog extends StatefulWidget {
  final Map<String, dynamic> promo;
  final Color accentColor;
  const _PromoHighlightDialog({required this.promo, required this.accentColor});

  @override
  State<_PromoHighlightDialog> createState() => _PromoHighlightDialogState();
}

class _PromoHighlightDialogState extends State<_PromoHighlightDialog> {
  late final ConfettiController _confettiCtrl;

  @override
  void initState() {
    super.initState();
    _confettiCtrl = ConfettiController(
      duration: const Duration(milliseconds: 1600),
    );
    // Laisse l'animation d'entrée du dialogue démarrer avant l'explosion,
    // sinon les deux animations simultanées se marchent dessus visuellement.
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _confettiCtrl.play();
    });
  }

  @override
  void dispose() {
    _confettiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final promo = widget.promo;
    final accentColor = widget.accentColor;
    final name = promo['name'] as String? ?? '';
    final deadline = _describeDeadline(promo);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 34),
            padding: const EdgeInsets.fromLTRB(24, 42, 24, 22),
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
                if (deadline != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 13,
                          color: accentColor,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          deadline,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: accentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
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
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Badge festif + explosion de confettis — remplace l'icône statique
          // d'origine, chevauche le haut du carton.
          IgnorePointer(
            child: SizedBox(
              width: 260,
              height: 200,
              child: ConfettiWidget(
                confettiController: _confettiCtrl,
                blastDirectionality: BlastDirectionality.explosive,
                shouldLoop: false,
                numberOfParticles: 28,
                gravity: 0.28,
                maxBlastForce: 20,
                minBlastForce: 9,
                emissionFrequency: 0.0,
                colors: [
                  accentColor,
                  Colors.amber,
                  Colors.pinkAccent,
                  Colors.greenAccent.shade400,
                  Colors.orangeAccent,
                ],
              ),
            ),
          ),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [accentColor, accentColor.withValues(alpha: 0.7)],
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.celebration_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),

          // Fermer sans forcer l'action "Super !"
          Positioned(
            top: 34,
            right: 4,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.06),
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
