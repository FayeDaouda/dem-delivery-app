import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Enveloppe un widget tapable avec un léger effet d'échelle au toucher.
///
/// Un `GestureDetector` nu ne donne aucun retour visuel avant que l'action
/// ne se déclenche — sur une carte ou une tuile de liste, ça donne une
/// impression de lenteur/absence de réaction. `InkWell` réglerait ça mais
/// impose un `Material` ancêtre et un ripple qui ne convient pas à tous les
/// designs (cartes à coins très arrondis, fonds dégradés...). Ce widget
/// donne le même bénéfice (retour immédiat au doigt) sans ces contraintes.
///
/// Le relâchement utilise une courbe avec léger dépassement (`easeOutBack`)
/// plutôt qu'un retour plat — sensation plus "physique", moins mécanique.
/// Appliqué à tous les usages du widget (amélioration neutre partout) ; le
/// retour haptique reste opt-in (`haptic`) pour ne pas l'imposer aux listes
/// à taps fréquents où il deviendrait vite fatigant.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.haptic = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: interactive
          ? (_) {
              if (widget.haptic) HapticFeedback.lightImpact();
              _setPressed(true);
            }
          : null,
      onTapCancel: interactive ? () => _setPressed(false) : null,
      onTapUp: interactive ? (_) => _setPressed(false) : null,
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: Duration(milliseconds: _pressed ? 100 : 220),
        curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
