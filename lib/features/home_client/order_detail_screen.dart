import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../../core/utils/price_format.dart';
import '../deliveries/providers/orders_provider.dart';
import '../../shared/widgets/address_row.dart';

const _kStatusLabel = {
  'SCHEDULED': 'Programmée',
  'PENDING': 'En attente',
  'ACCEPTED': 'Acceptée',
  'PICKED_UP': 'En route',
  'IN_TRANSIT': 'En cours',
  'DELIVERED': 'Livrée',
  'CANCELLED': 'Annulée',
};

const _kStatusColor = {
  'SCHEDULED': AppColors.pending,
  'PENDING': AppColors.warning,
  'ACCEPTED': AppColors.accentIndigo,
  'PICKED_UP': Color(0xFF9C27B0),
  'IN_TRANSIT': AppColors.accentIndigo,
  'DELIVERED': AppColors.successBright,
  'CANCELLED': AppColors.error,
};

String _fmtScheduled(dynamic raw) {
  final date = DateTime.tryParse(raw as String? ?? '')?.toLocal();
  if (date == null) return '';
  const jours = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
  final j = jours[date.weekday - 1];
  final hh = date.hour.toString().padLeft(2, '0');
  final mm = date.minute.toString().padLeft(2, '0');
  return '$j ${date.day}/${date.month} à $hh:$mm';
}

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
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.gradientDialog),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 20, 4),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
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
                    child: CircularProgressIndicator(color: Colors.white),
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
    final statusColor = _kStatusColor[status] ?? Colors.white70;
    final statusLabel = _kStatusLabel[status] ?? status;
    final price = (order['price'] as num?)?.toInt() ?? 0;
    final charge = clientChargeFor(order);
    final hasDiscount = charge < price;
    final pickup = order['pickupAddress'] as String? ?? '—';
    final delivery = order['deliveryAddress'] as String? ?? '—';
    final driver = order['driver'] as Map?;
    final driverName = driver?['name'] as String?;
    final driverAvatar = driver?['avatar'] as String?;
    final driverRating = (driver?['averageRating'] as num?)?.toDouble();
    final proofPhotoUrl = order['proofPhotoUrl'] as String?;
    final hasProofPhoto = proofPhotoUrl != null && proofPhotoUrl.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor.withValues(alpha: 0.4)),
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

        // ── Créneau programmé ──
        if (status == 'SCHEDULED' && order['scheduledAt'] != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule_outlined, size: 16, color: Colors.white70),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Livraison programmée — ${_fmtScheduled(order['scheduledAt'])}',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Tant qu'aucun livreur n'a réservé le créneau — recherche en
          // cours en tâche de fond côté serveur (voir scheduled-dispatch.service.js).
          if (driverName == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.pending.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.pending),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Recherche d\'un livreur pour ce créneau…',
                      style: TextStyle(color: AppColors.pending, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          if (driverName == null) const SizedBox(height: 14),
        ],

        // ── Carte livreur ──
        if (driverName != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  backgroundImage: driverAvatar != null
                      ? NetworkImage(driverAvatar)
                      : null,
                  child: driverAvatar == null
                      ? const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 24,
                        )
                      : null,
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
                      // Distingue d'un livreur "en route" — celui-ci est
                      // engagé pour le créneau programmé, pas encore en course.
                      if (status == 'SCHEDULED') ...[
                        const SizedBox(height: 3),
                        const Text(
                          'Assigné pour votre créneau',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // ── Carte trajet ──
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
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
        const SizedBox(height: 14),

        // ── Carte prix ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.payments_outlined,
                size: 16,
                color: Colors.white70,
              ),
              const SizedBox(width: 8),
              const Text(
                'Montant payé',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const Spacer(),
              if (!hasDiscount)
                // charge inclut demFee (frais DEM éventuels) — jamais price
                // seul, qui reste 100% pour le livreur (clientChargeFor).
                Text(
                  formatFcfa(charge),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
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
                    color: AppColors.successBright,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),

        // Preuve de livraison — section toujours affichée pour une commande
        // livrée (même sans photo, état vide explicite) plutôt que masquée
        // en silence : sans ça, impossible de distinguer "le livreur n'a
        // pas pris de photo" d'un bug d'affichage.
        if (status == 'DELIVERED') ...[
          const SizedBox(height: 14),
          Text(
            'Preuve de livraison',
            style: ClientText.bodyStrong.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          if (hasProofPhoto)
            GestureDetector(
              onTap: () => _showFullscreenPhoto(context, proofPhotoUrl),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  proofPhotoUrl,
                  width: double.infinity,
                  height: 220,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      height: 220,
                      color: Colors.white.withValues(alpha: 0.08),
                      child: const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stack) => Container(
                    height: 220,
                    color: Colors.white.withValues(alpha: 0.08),
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
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.photo_camera_outlined,
                    color: Colors.white38,
                    size: 26,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Aucune photo prise pour cette livraison',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                    ),
                  ),
                ],
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
