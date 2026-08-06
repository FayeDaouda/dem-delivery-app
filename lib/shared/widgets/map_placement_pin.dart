import 'dart:math';

import 'package:flutter/material.dart';

/// Épingle flottante centrée sur la carte en mode "pointer sur la carte" —
/// suit implicitement le centre de l'écran (le parent la positionne), flotte
/// doucement pour signaler "ceci bouge avec la carte, pas un marqueur fixe".
/// Partagée entre Livraison simple/Express et Livraison groupée.
class MapPlacementPin extends StatefulWidget {
  final Color color;
  const MapPlacementPin({super.key, required this.color});

  @override
  State<MapPlacementPin> createState() => _MapPlacementPinState();
}

class _MapPlacementPinState extends State<MapPlacementPin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _floatAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(
      begin: 0,
      end: -6,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _floatAnim,
      builder: (_, _) => Transform.translate(
        offset: Offset(0, _floatAnim.value),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: -pi / 4,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.5),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Transform.rotate(
                    angle: pi / 4,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Color(0xFF080D1A),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, _) => Container(
                width: 18,
                height: 6,
                decoration: BoxDecoration(
                  color: widget.color.withValues(
                    alpha: 0.25 + 0.15 * _ctrl.value,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bandeau "Valider ce point" affiché sous l'épingle centrale en mode
/// placement — remplace le contenu normal de la feuille du bas tant que le
/// client n'a pas confirmé où poser le point.
class MapPlacementConfirmPanel extends StatelessWidget {
  final Color color;
  final String label;
  final VoidCallback onConfirm;
  final VoidCallback? onCancel;
  const MapPlacementConfirmPanel({
    super.key,
    required this.color,
    required this.label,
    required this.onConfirm,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onConfirm,
              icon: const Icon(Icons.check_circle_outline, size: 20),
              label: Text(label),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (onCancel != null) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: onCancel,
              child: const Text(
                'Annuler',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
