import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Anneau qui pulse en boucle continue autour d'un point de la carte — même
/// principe que le marqueur "ma position" de l'écran d'accueil livreur
/// (`home_driver_screen.dart`) : un widget Flutter positionné en pixels
/// écran (pas un `Circle` ancré en coordonnées réelles), qui grandit et
/// s'estompe indéfiniment tant que l'écran est affiché.
///
/// [position] doit être recalculé par l'appelant (via
/// `GoogleMapController.getScreenCoordinate`) à chaque fois que le point
/// suivi ou la caméra bouge — ce widget se contente de l'afficher et de
/// l'animer, il ne suit pas la carte tout seul.
class ScreenPulseRing extends StatefulWidget {
  const ScreenPulseRing({super.key, required this.position, required this.color, this.size = 60});

  final ScreenCoordinate? position;
  final Color color;
  final double size;

  @override
  State<ScreenPulseRing> createState() => _ScreenPulseRingState();
}

class _ScreenPulseRingState extends State<ScreenPulseRing> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
    _scale = Tween<double>(begin: 0.4, end: 2.2).animate(_ctrl);
    _opacity = Tween<double>(begin: 0.7, end: 0.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pos = widget.position;
    if (pos == null) return const SizedBox.shrink();
    return Positioned(
      left: pos.x.toDouble() - widget.size / 2,
      top: pos.y.toDouble() - widget.size / 2,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) => Transform.scale(
            scale: _scale.value,
            child: Opacity(opacity: _opacity.value, child: child),
          ),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: widget.color, width: 2.5),
            ),
          ),
        ),
      ),
    );
  }
}
