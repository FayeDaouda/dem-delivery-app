import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../../core/utils/price_format.dart';
import '../deliveries/providers/orders_provider.dart';
import '../../shared/widgets/address_row.dart';

const _kStatusLabel = {
  'PENDING': 'En attente',
  'ACCEPTED': 'Acceptée',
  'PICKED_UP': 'En route',
  'IN_TRANSIT': 'En cours',
  'DELIVERED': 'Livrée',
  'CANCELLED': 'Annulée',
};

const _kStatusColor = {
  'PENDING': AppColors.warning,
  'ACCEPTED': AppColors.accentIndigo,
  'PICKED_UP': Color(0xFF9C27B0),
  'IN_TRANSIT': AppColors.accentIndigo,
  'DELIVERED': AppColors.successLight,
  'CANCELLED': AppColors.error,
};

/// Détail d'une commande passée — écran "reçu", pas de suivi temps réel
/// (contrairement à order_tracking_screen.dart, pensé pour une course en
/// cours). Sert notamment à consulter la photo de preuve de livraison après
/// coup, potentiellement des jours plus tard en cas de litige.
class OrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;
  final Map<String, dynamic>? initialOrder;
  const OrderDetailScreen({
    super.key,
    required this.orderId,
    this.initialOrder,
  });

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  Map<String, dynamic>? _order;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _order = widget.initialOrder;
    _load();
  }

  // Toujours re-fetché même si initialOrder est fourni (venant de la liste
  // paginée) — la photo de preuve peut avoir été ajoutée par le livreur
  // après le chargement de cette liste.
  Future<void> _load() async {
    try {
      final fresh = await ref
          .read(ordersRepositoryProvider)
          .getOrderById(widget.orderId);
      if (mounted) setState(() => _order = fresh);
    } catch (e) {
      if (mounted && _order == null) {
        setState(() => _error = 'Impossible de charger la commande.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Détail de la commande',
                    style: ClientText.subtitle.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
            if (_loading && order == null)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else if (order == null)
              Expanded(
                child: Center(
                  child: Text(
                    _error ?? 'Commande introuvable.',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              )
            else
              Expanded(child: _OrderDetailBody(order: order)),
          ],
        ),
      ),
    );
  }
}

class _OrderDetailBody extends StatelessWidget {
  final Map<String, dynamic> order;
  const _OrderDetailBody({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = (order['status'] as String? ?? '').toUpperCase();
    final statusColor = _kStatusColor[status] ?? AppColors.textMuted;
    final statusLabel = _kStatusLabel[status] ?? status;
    final price = (order['price'] as num?)?.toInt() ?? 0;
    final charge = clientChargeFor(order);
    final hasDiscount = charge < price;
    final pickup = order['pickupAddress'] as String? ?? '—';
    final delivery = order['deliveryAddress'] as String? ?? '—';
    final driver = order['driver'] as Map?;
    final driverName = driver?['name'] as String?;
    final driverRating = (driver?['averageRating'] as num?)?.toDouble();
    final proofPhotoUrl = order['proofPhotoUrl'] as String?;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_shipping_outlined, color: statusColor, size: 16),
              const SizedBox(width: 8),
              Text(
                statusLabel,
                style: ClientText.body.copyWith(color: statusColor),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (driverName != null) ...[
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driverName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (driverRating != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: AppColors.ratingGold,
                            size: 14,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            driverRating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              AddressRow(
                icon: Icons.circle,
                iconColor: AppColors.successBright,
                address: pickup,
                dark: true,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Container(
                  width: 2,
                  height: 12,
                  color: Colors.white.withValues(alpha: 0.25),
                ),
              ),
              AddressRow(
                icon: Icons.location_on,
                iconColor: AppColors.error,
                address: delivery,
                dark: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            const Icon(
              Icons.payments_outlined,
              size: 16,
              color: Colors.white70,
            ),
            const SizedBox(width: 6),
            if (!hasDiscount)
              Text(
                formatFcfa(price),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              )
            else ...[
              Text(
                formatFcfa(price),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                formatFcfa(charge),
                style: const TextStyle(
                  color: AppColors.successLight,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),

        // Preuve de livraison — n'existe que si le livreur a choisi d'en
        // prendre une (optionnel), donc absente pour la plupart des
        // commandes. Utile surtout en cas de litige, potentiellement
        // consultée bien après la livraison, d'où cet écran persistant.
        if (proofPhotoUrl != null && proofPhotoUrl.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Preuve de livraison',
            style: ClientText.bodyStrong.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _showFullscreenPhoto(context, proofPhotoUrl),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                proofPhotoUrl,
                width: double.infinity,
                height: 220,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    height: 220,
                    color: Colors.white.withValues(alpha: 0.06),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stack) => Container(
                  height: 220,
                  color: Colors.white.withValues(alpha: 0.06),
                  child: const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white38,
                      size: 32,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showFullscreenPhoto(BuildContext context, String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: InteractiveViewer(
              child: Image.network(
                url,
                errorBuilder: (context, error, stack) {
                  return const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white38,
                    size: 48,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
