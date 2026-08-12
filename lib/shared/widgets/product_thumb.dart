import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Vignette produit — affiche l'image si le DEM Pro en a mis une, sinon une
/// icône générique (photo optionnelle, jamais bloquante pour le catalogue).
class ProductThumb extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final BorderRadius? borderRadius;
  final IconData fallbackIcon;

  const ProductThumb({
    super.key,
    required this.imageUrl,
    this.size = 42,
    this.borderRadius,
    this.fallbackIcon = Icons.inventory_2_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(10);
    final url = imageUrl;

    if (url == null || url.isEmpty) {
      return _fallback(radius);
    }
    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(radius),
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _fallback(radius),
      ),
    );
  }

  Widget _fallback(BorderRadius radius) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: 0.10),
      borderRadius: radius,
    ),
    child: Icon(fallbackIcon, color: AppColors.primary, size: size * 0.48),
  );
}
