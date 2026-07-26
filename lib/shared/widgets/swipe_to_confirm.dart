import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bouton "glisser pour confirmer" — remplace un bouton tap classique pour les
/// actions à fort enjeu (accepter une course, confirmer une récupération/
/// livraison) que le livreur pourrait déclencher par erreur avec le téléphone
/// en poche.
///
/// Glissement complet du curseur jusqu'au bout -> le curseur termine sa
/// course avec un rebond et l'icône se transforme en check avant que
/// [onConfirmed] soit appelé. Relâché avant le seuil -> le curseur revient
/// au départ. Pendant [loading], le curseur reste verrouillé en position
/// finale avec un indicateur de chargement.
///
/// Si l'action échoue et que l'écran reste affiché (pas de navigation), le
/// parent doit changer la [key] du widget (ex. incrémenter un compteur inclus
/// dans une `ValueKey`) pour réinitialiser visuellement le curseur — sans ça,
/// il resterait verrouillé en position "confirmé" sans possibilité de réessayer.
class SwipeToConfirm extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color trackColor;
  final Color thumbColor;
  final Color iconColor;
  final Color labelColor;
  final bool loading;
  final VoidCallback onConfirmed;

  /// Quand false, le curseur est verrouillé (grisé, cadenas) et ne peut pas
  /// être glissé — utilisé pour bloquer la confirmation "récupéré"/"livré"
  /// tant que le livreur n'est pas à proximité du point (évite les clics
  /// accidentels qui font perdre l'itinéraire en cours).
  final bool enabled;

  /// Texte affiché à la place de [label] quand [enabled] est false.
  final String? lockedLabel;

  /// Appelé quand le livreur tente de glisser alors que [enabled] est false
  /// — utile pour afficher un message explicatif (ex. distance restante).
  final VoidCallback? onLockedTap;

  /// 0..1 — à quel point on se rapproche du déverrouillage (proximité GPS).
  /// Dessine un arc de progression autour du cadenas quand [enabled] est false.
  final double lockProgress;

  const SwipeToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.icon = Icons.arrow_forward_rounded,
    required this.trackColor,
    required this.thumbColor,
    required this.iconColor,
    required this.labelColor,
    this.loading = false,
    this.enabled = true,
    this.lockedLabel,
    this.onLockedTap,
    this.lockProgress = 0,
  });

  @override
  State<SwipeToConfirm> createState() => _SwipeToConfirmState();
}

class _SwipeToConfirmState extends State<SwipeToConfirm> with TickerProviderStateMixin {
  late final AnimationController _snapBackCtrl;
  late final AnimationController _completeCtrl;
  late final AnimationController _shakeCtrl;

  Animation<double> _snapBackAnim = const AlwaysStoppedAnimation(0);
  Animation<double> _completeExtentAnim = const AlwaysStoppedAnimation(1);
  Animation<double> _completeScaleAnim = const AlwaysStoppedAnimation(1);

  double _extent = 0; // position du curseur le long de la piste, 0..1
  bool _confirmed = false;
  int _lastHapticStep = -1;

  static const double _thumbSize = 48;
  static const double _height = 56;
  static const double _padding = 4;
  static const double _threshold = 0.78;

  @override
  void initState() {
    super.initState();
    _snapBackCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250))
      ..addListener(() => setState(() => _extent = _snapBackAnim.value));

    // Anime la fin du glissement jusqu'au bout (au lieu d'un saut instantané)
    // puis fait rebondir légèrement le curseur avant de déclencher l'action —
    // donne une sensation de "sceau" plutôt qu'un à-coup.
    _completeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 340))
      ..addListener(() => setState(() => _extent = _completeExtentAnim.value))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() => _confirmed = true);
          HapticFeedback.mediumImpact();
          widget.onConfirmed();
        }
      });

    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
  }

  @override
  void dispose() {
    _snapBackCtrl.dispose();
    _completeCtrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  bool get _locked => widget.loading || _confirmed || _completeCtrl.isAnimating;
  bool get _dragBlocked => _locked || !widget.enabled;

  void _onLockedAttempt() {
    if (!widget.enabled && !_locked) {
      HapticFeedback.selectionClick();
      _shakeCtrl.forward(from: 0);
      widget.onLockedTap?.call();
    }
  }

  void _onDragStart() {
    _lastHapticStep = -1;
  }

  void _onDragUpdate(DragUpdateDetails d, double maxDrag) {
    if (_dragBlocked || maxDrag <= 0) return;
    final newExtent = (_extent + d.delta.dx / maxDrag).clamp(0.0, 1.0);
    // Petit tick haptique à chaque quart parcouru — comme les sliders iOS —
    // plutôt qu'un seul impact au bout, plus perceptible et "premium".
    final step = (newExtent * 4).floor().clamp(0, 3);
    if (step > _lastHapticStep) HapticFeedback.selectionClick();
    _lastHapticStep = step;
    setState(() => _extent = newExtent);
  }

  void _onDragEnd(DragEndDetails d, double maxDrag) {
    if (_dragBlocked) return;
    if (_extent >= _threshold) {
      _completeExtentAnim = Tween<double>(begin: _extent, end: 1.0)
          .animate(CurvedAnimation(parent: _completeCtrl, curve: Curves.easeOutCubic));
      _completeScaleAnim = TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.16).chain(CurveTween(curve: Curves.easeOut)), weight: 55),
        TweenSequenceItem(tween: Tween(begin: 1.16, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 45),
      ]).animate(_completeCtrl);
      _completeCtrl.forward(from: 0);
    } else {
      _snapBackAnim = Tween<double>(begin: _extent, end: 0.0)
          .animate(CurvedAnimation(parent: _snapBackCtrl, curve: Curves.easeOut));
      _snapBackCtrl.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = !widget.enabled && !_locked;
    final trackColor = isLocked ? const Color(0xFF4B5A6B) : widget.trackColor;
    final thumbColor = isLocked ? const Color(0xFF8CA0B3) : widget.thumbColor;
    final iconColor = isLocked ? Colors.white : widget.iconColor;
    final labelColor = isLocked ? Colors.white70 : widget.labelColor;
    final label = isLocked ? (widget.lockedLabel ?? widget.label) : widget.label;
    final thumbScale = _completeCtrl.isAnimating ? _completeScaleAnim.value : 1.0;

    return LayoutBuilder(builder: (context, constraints) {
      final maxDrag = (constraints.maxWidth - _thumbSize - _padding * 2).clamp(0.0, double.infinity);
      final thumbLeft = _padding + _extent * maxDrag;
      final fillWidth = (thumbLeft + _thumbSize / 2).clamp(0.0, constraints.maxWidth);

      return SizedBox(
        height: _height,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            GestureDetector(
              onTap: isLocked ? _onLockedAttempt : null,
              child: Container(
                width: double.infinity,
                height: _height,
                decoration: BoxDecoration(
                  color: trackColor,
                  borderRadius: BorderRadius.circular(_height / 2),
                ),
                child: Center(
                  child: widget.loading
                      ? SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: widget.labelColor),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: _thumbSize + 8),
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: labelColor.withValues(alpha: (1 - _extent * 1.3).clamp(0.0, 1.0)),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            // Remplissage progressif derrière le curseur — feedback continu
            // pendant le glissement plutôt qu'un simple texte qui s'efface.
            if (!widget.loading && !isLocked)
              IgnorePointer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_height / 2),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: fillWidth,
                      height: _height,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            widget.thumbColor.withValues(alpha: 0.0),
                            widget.thumbColor.withValues(alpha: 0.28),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (!widget.loading)
              AnimatedBuilder(
                animation: _shakeCtrl,
                builder: (context, child) {
                  final t = _shakeCtrl.value;
                  final shake = (t == 0 || t == 1) ? 0.0 : math.sin(t * math.pi * 3) * (1 - t) * 8;
                  return Positioned(left: thumbLeft + shake, child: child!);
                },
                child: GestureDetector(
                  onTap: isLocked ? _onLockedAttempt : null,
                  onHorizontalDragStart: isLocked ? (_) => _onLockedAttempt() : (_) => _onDragStart(),
                  onHorizontalDragUpdate: (d) => _onDragUpdate(d, maxDrag),
                  onHorizontalDragEnd: (d) => _onDragEnd(d, maxDrag),
                  child: Transform.scale(
                    scale: thumbScale,
                    child: Container(
                      width: _thumbSize,
                      height: _thumbSize,
                      decoration: BoxDecoration(
                        color: thumbColor,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6)],
                      ),
                      child: CustomPaint(
                        painter: isLocked
                            ? _LockRingPainter(progress: widget.lockProgress, color: Colors.white)
                            : null,
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            transitionBuilder: (child, anim) =>
                                ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
                            child: Icon(
                              _confirmed ? Icons.check_rounded : (isLocked ? Icons.lock_outline : widget.icon),
                              key: ValueKey(_confirmed ? 'check' : (isLocked ? 'lock' : 'arrow')),
                              color: iconColor,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

/// Anneau de progression dessiné autour du cadenas — indique à quel point le
/// livreur se rapproche de la zone de confirmation (500 m) plutôt qu'un
/// simple état bloqué/débloqué binaire.
class _LockRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  _LockRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 3;
    final bg = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, radius, bg);

    final clamped = progress.clamp(0.0, 1.0);
    if (clamped > 0) {
      final fg = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * clamped,
        false,
        fg,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LockRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
