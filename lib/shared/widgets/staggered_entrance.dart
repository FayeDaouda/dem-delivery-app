import 'package:flutter/material.dart';

/// Entrée en fondu + léger glissement vertical, décalée par [index] — donne
/// une impression de fluidité à l'apparition d'une liste de cartes (au lieu
/// qu'elles apparaissent toutes d'un bloc), effet courant sur les apps
/// premium (Revolut, Cash App). Extrait de home_client_screen.dart (tuiles
/// Simple/Express/Groupée) pour être réutilisable partout dans l'app.
class StaggeredEntrance extends StatefulWidget {
  final int index;
  final Widget child;
  final Duration delayPerIndex;
  final Duration duration;
  final Offset beginOffset;

  const StaggeredEntrance({
    super.key,
    required this.index,
    required this.child,
    this.delayPerIndex = const Duration(milliseconds: 70),
    this.duration = const Duration(milliseconds: 340),
    this.beginOffset = const Offset(0, 0.18),
  });

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delayPerIndex * widget.index, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: _visible ? Offset.zero : widget.beginOffset,
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: widget.duration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
