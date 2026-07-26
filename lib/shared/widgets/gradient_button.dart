import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class GradientButton extends StatelessWidget {
  final String label;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onDisabledTap;
  final double height;

  const GradientButton({
    super.key,
    required this.label,
    required this.onTap,
    this.loading = false,
    this.enabled = true,
    this.onDisabledTap,
    this.height = 54,
  });

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: active ? onTap : (onDisabledTap ?? () {}),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: height,
        decoration: BoxDecoration(
          color: !active ? Colors.white.withValues(alpha: 0.4) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: !active
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(color: AppColors.primaryMid, strokeWidth: 2),
                )
              : Text(
                  label,
                  style: TextStyle(
                    color: enabled
                        ? AppColors.primaryDark
                        : AppColors.primaryDark.withValues(alpha: 0.45),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
        ),
      ),
    );
  }
}
