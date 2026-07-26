import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import 'nudging_chevron.dart';

/// CTA plein-largeur coloré/dégradé posé sur un panneau ou une carte — par
/// opposition à [GradientButton] (bouton blanc sur fond plein écran
/// dégradé). Généralisé depuis le `_NextButton` du wizard de création de
/// commande, qui avait le meilleur comportement (anim de "pop" à
/// l'activation, scale au press, état loading) mais était privé à cet
/// écran — dupliqué avec des variantes légèrement différentes ailleurs.
class PrimaryButton extends StatefulWidget {
  final String label;
  final IconData? leadingIcon;
  final IconData? trailingIcon; // rendu avec l'anim "nudge" — style "étape suivante"
  final VoidCallback? onTap;
  final bool loading;

  /// Fond uni (ex. vert succès). Si null, utilise [gradient] (par défaut
  /// `AppColors.gradientCta`).
  final Color? color;
  final Gradient? gradient;

  /// Par défaut : blanc sur fond uni, noir sur le dégradé cyan (meilleur
  /// contraste sur `gradientCta`, qui est clair).
  final Color? foregroundColor;
  final double height;

  /// Fond à l'état désactivé — par défaut un blanc translucide pensé pour
  /// les panneaux sombres (sheets dégradées). À surcharger explicitement
  /// sur un fond clair (sheet blanche), sous peine d'un bouton désactivé
  /// quasi invisible.
  final Color? disabledColor;

  const PrimaryButton({
    super.key,
    required this.label,
    this.leadingIcon,
    this.trailingIcon,
    this.onTap,
    this.loading = false,
    this.color,
    this.gradient,
    this.foregroundColor,
    this.height = 52,
    this.disabledColor,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _popCtrl;
  late final Animation<double> _popScale;

  bool get _active => widget.onTap != null && !widget.loading;

  @override
  void initState() {
    super.initState();
    _popCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _popScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.06).chain(CurveTween(curve: Curves.easeOut)), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.06, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 55),
    ]).animate(_popCtrl);
  }

  @override
  void didUpdateWidget(covariant PrimaryButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // "Pop" quand le bouton passe de désactivé à actif — signale clairement
    // qu'une condition vient d'être remplie, pile au bon moment.
    final wasActive = oldWidget.onTap != null && !oldWidget.loading;
    if (!wasActive && _active) _popCtrl.forward(from: 0);
  }

  @override
  void dispose() {
    _popCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    final glow = widget.color ?? const Color(0xFF00D4FF);
    final fg = !active
        ? const Color(0xFF5A6A8A)
        : widget.foregroundColor ?? (widget.color != null ? Colors.white : Colors.black);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: active ? widget.onTap : null,
      onTapDown: active ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: AnimatedBuilder(
        animation: _popCtrl,
        builder: (context, child) => Transform.scale(
          scale: (_pressed ? 0.97 : 1.0) * _popScale.value,
          child: child,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          height: widget.height,
          decoration: BoxDecoration(
            gradient: active && widget.color == null ? (widget.gradient ?? AppColors.gradientCta) : null,
            color: !active ? (widget.disabledColor ?? Colors.white.withValues(alpha: 0.06)) : widget.color,
            borderRadius: BorderRadius.circular(18),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: glow.withValues(alpha: _pressed ? 0.16 : 0.30),
                      blurRadius: _pressed ? 14 : 28,
                      offset: Offset(0, _pressed ? 3 : 8),
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: widget.loading
                ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: fg, strokeWidth: 2))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.leadingIcon != null) ...[
                        Icon(widget.leadingIcon, color: fg, size: 18),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        widget.label,
                        style: ClientText.button.copyWith(color: fg, letterSpacing: 0.3),
                      ),
                      if (widget.trailingIcon != null) ...[
                        const SizedBox(width: 8),
                        NudgingChevron(icon: widget.trailingIcon!, color: fg, size: 16),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
