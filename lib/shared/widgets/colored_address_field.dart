import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Champ d'adresse "flottant" sur une carte — fond blanc quasi-opaque (80%,
/// jamais un lavis translucide dont la lisibilité dépendrait de ce qu'il y a
/// sous le champ sur la carte), bordure colorée (vert départ / rouge
/// destination, ambre si le texte tapé n'a pas encore été confirmé par une
/// sélection). Utilisé par le flux de commande simple/Express et par la
/// tournée groupée — un seul composant, un seul endroit à corriger.
class AddressField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final Color dotColor;
  final bool active;
  // Adresse dotée de coordonnées GPS (sélectionnée dans la liste, placée sur
  // la carte, ou géolocalisée) — par opposition à du texte simplement tapé
  // sans être choisi, qui a l'air identique mais ne permet pas de calculer
  // de trajet ni de prix.
  final bool confirmed;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;
  final VoidCallback? onMapTap;
  final VoidCallback? onDotLongPress;
  final VoidCallback? onClear;
  final FocusNode? focusNode;
  // Tant que true, le champ affiche son texte mais ne s'ouvre pas au
  // clavier au tap direct — sert quand la saisie passe d'abord par un menu
  // de choix (position actuelle / favoris / carte / écrire) plutôt que par
  // la frappe immédiate. `onTap` continue de se déclencher normalement.
  final bool readOnly;

  static const _unconfirmedColor = Color(0xFFF59E0B);

  const AddressField({
    super.key,
    required this.controller,
    required this.hint,
    required this.dotColor,
    required this.active,
    required this.confirmed,
    required this.onTap,
    required this.onChanged,
    this.onMapTap,
    this.onDotLongPress,
    this.onClear,
    this.focusNode,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasText = controller.text.isNotEmpty;
    final needsConfirmation = hasText && !confirmed;
    final accentColor = needsConfirmation ? _unconfirmedColor : dotColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.80),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: accentColor.withValues(alpha: active ? 1.0 : 0.65),
            width: active ? 1.4 : 1.0,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.22),
                    blurRadius: 20,
                    spreadRadius: 0,
                  ),
                ]
              : [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.08),
                    blurRadius: 6,
                  ),
                ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onDotLongPress,
              onLongPress: onDotLongPress,
              child: active
                  ? PulsingDot(color: dotColor)
                  : Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                onTap: onTap,
                readOnly: readOnly,
                showCursor: !readOnly,
                textInputAction: TextInputAction.search,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 14.5,
                ),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14.5,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  isDense: true,
                  fillColor: Colors.transparent,
                  filled: true,
                ),
              ),
            ),
            if (needsConfirmation)
              const Padding(
                padding: EdgeInsets.only(right: 2),
                child: Icon(
                  Icons.error_outline,
                  color: _unconfirmedColor,
                  size: 16,
                ),
              ),
            if (hasText)
              IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppColors.textMuted,
                  size: 18,
                ),
                onPressed: onClear,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
              ),
            if (onMapTap != null)
              IconButton(
                icon: Icon(
                  Icons.location_on,
                  color: active ? dotColor : AppColors.textMuted,
                  size: 20,
                ),
                onPressed: onMapTap,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                constraints: const BoxConstraints(),
              ),
          ],
        ),
      ),
    );
  }
}

/// Point coloré pulsé — indique le champ actuellement actif/en édition.
class PulsingDot extends StatefulWidget {
  final Color color;
  const PulsingDot({super.key, required this.color});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.4 + 0.3 * _ctrl.value),
              blurRadius: 8 + 6 * _ctrl.value,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}
