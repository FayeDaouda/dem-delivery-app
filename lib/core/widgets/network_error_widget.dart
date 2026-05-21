import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Widget d'erreur réseau réutilisable.
/// Affiche un message centré avec un bouton "Réessayer".
class NetworkErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final bool sliver;

  const NetworkErrorWidget({
    super.key,
    required this.message,
    required this.onRetry,
    this.sliver = false,
  });

  Widget _content() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.wifi_off_rounded, size: 36, color: Colors.orange.shade400),
        ),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF6B7280),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Réessayer'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryMid,
            side: const BorderSide(color: AppColors.primaryMid),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (sliver) return SliverToBoxAdapter(child: _content());
    return Center(child: _content());
  }
}
