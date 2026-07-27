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
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

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
      onTapDown: interactive ? (_) => _setPressed(true) : null,
      onTapCancel: interactive ? () => _setPressed(false) : null,
      onTapUp: interactive ? (_) => _setPressed(false) : null,
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
