import 'package:flutter/material.dart';

/// Icône qui glisse doucement d'avant en arrière puis marque une pause, en
/// boucle — invite subtilement au tap sur un CTA sans animation permanente
/// distrayante. Utilisée sur les boutons d'action principaux (carte
/// "Livraison" de l'accueil, bouton "Suivant" de la création de commande...).
class NudgingChevron extends StatefulWidget {
  const NudgingChevron({
    super.key,
    this.icon = Icons.arrow_forward_ios,
    required this.color,
    this.size = 16,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  State<NudgingChevron> createState() => _NudgingChevronState();
}

class _NudgingChevronState extends State<NudgingChevron> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _offset;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
    _offset = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 4.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 4.0, end: 0.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 25),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 50),
    ]).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      builder: (context, child) => Transform.translate(offset: Offset(_offset.value, 0), child: child),
      child: Icon(widget.icon, color: widget.color, size: widget.size),
    );
  }
}
