import 'package:flutter/material.dart';

/// Enveloppe un widget tapable avec un léger effet d'échelle au toucher.
///
/// Un `GestureDetector` nu ne donne aucun retour visuel avant que l'action
/// ne se déclenche — sur une carte ou une tuile de liste, ça donne une
/// impression de lenteur/absence de réaction. `InkWell` réglerait ça mais
/// impose un `Material` ancêtre et un ripple qui ne convient pas à tous les
/// designs (cartes à coins très arrondis, fonds dégradés...). Ce widget
/// donne le même bénéfice (retour immédiat au doigt) sans ces contraintes.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.darkenOnPress = false,
    this.darkenBorderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  /// Assombrit légèrement le contenu au toucher, en plus du scale — retour
  /// tactile plus qualitatif pour les cartes premium (service cards, etc.).
  /// Désactivé par défaut pour ne rien changer aux usages existants.
  final bool darkenOnPress;

  /// Doit correspondre au rayon d'arrondi du [child] pour que le voile
  /// sombre épouse exactement ses coins — sans quoi il déborderait en
  /// rectangle sur un [child] aux coins arrondis.
  final BorderRadius? darkenBorderRadius;

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
    Widget child = widget.child;
    if (widget.darkenOnPress) {
      child = AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        foregroundDecoration: BoxDecoration(
          color: Colors.black.withValues(alpha: _pressed ? 0.10 : 0),
          borderRadius: widget.darkenBorderRadius,
        ),
        child: child,
      );
    }
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: interactive ? (_) => _setPressed(true) : null,
      onTapCancel: interactive ? () => _setPressed(false) : null,
      onTapUp: interactive ? (_) => _setPressed(false) : null,
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: child,
      ),
    );
  }
}
