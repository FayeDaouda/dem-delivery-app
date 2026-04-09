import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

/// Affiché après la création d'une commande.
/// Reçoit l'objet `order` retourné par le backend.
class OrderConfirmationScreen extends StatelessWidget {
  final Map<String, dynamic> order;
  const OrderConfirmationScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final price           = order['price'] as num?;
    final surge           = (order['surgeMultiplier'] as num?)?.toDouble() ?? 1.0;
    final etaPickup       = order['etaPickupMin'] as int?;
    final etaDelivery     = order['etaDeliveryMin'] as int?;
    final pickupAddress   = order['pickupAddress'] as String? ?? '';
    final deliveryAddress = order['deliveryAddress'] as String? ?? '';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),

              // ── Icône succès ──
              Container(
                width: 80, height: 80,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.primary, Color(0xFF1A6B7A)],
                  ),
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 44),
              ),
              const SizedBox(height: 20),
              const Text('Course commandée !',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Recherche d\'un driver en cours…',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),

              const SizedBox(height: 32),

              // ── Carte détails ──
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(18),
                  border: surge > 1.0
                      ? Border.all(color: const Color(0xFFFF9800), width: 1.5)
                      : null,
                ),
                child: Column(children: [
                  _Row(icon: Icons.my_location,   label: 'Départ',    value: pickupAddress),
                  const Divider(color: AppColors.surface, height: 20),
                  _Row(icon: Icons.location_on,   label: 'Arrivée',   value: deliveryAddress),
                  const Divider(color: AppColors.surface, height: 20),
                  _Row(
                    icon: Icons.payments_outlined,
                    label: 'Prix',
                    value: '${price?.toInt() ?? '—'} FCFA',
                    valueStyle: const TextStyle(
                      color: AppColors.primary, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  if (surge > 1.0) ...[
                    const SizedBox(height: 12),
                    _SurgeBadge(multiplier: surge),
                  ],
                  if (etaPickup != null) ...[
                    const Divider(color: AppColors.surface, height: 20),
                    _Row(
                      icon: Icons.timer_outlined,
                      label: 'ETA arrivée driver',
                      value: '~$etaPickup min',
                    ),
                  ],
                  if (etaDelivery != null) ...[
                    const SizedBox(height: 4),
                    _Row(
                      icon: Icons.flag_outlined,
                      label: 'ETA livraison',
                      value: '~$etaDelivery min',
                    ),
                  ],
                ]),
              ),

              const Spacer(),

              // ── Bouton retour ──
              ElevatedButton(
                onPressed: () => context.go('/client/home'),
                child: const Text('Retour à l\'accueil'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final TextStyle? valueStyle;
  const _Row({required this.icon, required this.label, required this.value, this.valueStyle});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: AppColors.primary, size: 18),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: valueStyle ?? const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
        ]),
      ),
    ],
  );
}

class _SurgeBadge extends StatelessWidget {
  final double multiplier;
  const _SurgeBadge({required this.multiplier});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFFF9800).withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.local_fire_department, color: Color(0xFFFF9800), size: 16),
      const SizedBox(width: 6),
      Text('Forte demande — ×${multiplier.toStringAsFixed(1)} appliqué',
        style: const TextStyle(color: Color(0xFFFF9800), fontWeight: FontWeight.w600, fontSize: 13)),
    ]),
  );
}
