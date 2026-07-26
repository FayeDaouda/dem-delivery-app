import 'package:flutter/material.dart';

/// Rectangle "shimmer" — brique de base pour composer des écrans de
/// chargement qui épousent la forme du contenu final (skeleton) au lieu
/// d'un simple spinner générique centré. Donne une sensation de vitesse
/// perçue plus élevée, à latence réseau égale.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
    this.baseColor = const Color(0xFFE8ECF2),
    this.highlightColor = const Color(0xFFF6F8FB),
  });

  final double? width;
  final double height;
  final BorderRadius borderRadius;
  final Color baseColor;
  final Color highlightColor;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
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
      builder: (context, _) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) => LinearGradient(
          colors: [widget.baseColor, widget.highlightColor, widget.baseColor],
          stops: const [0.15, 0.4, 0.65],
          begin: Alignment(-1.0 - _ctrl.value * 2, 0),
          end: Alignment(1.0 - _ctrl.value * 2, 0),
        ).createShader(rect),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(color: Colors.white, borderRadius: widget.borderRadius),
        ),
      ),
    );
  }
}
