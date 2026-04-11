import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../features/deliveries/providers/orders_provider.dart';

// ── Provider historique client ────────────────────────────────────────────────
final myOrdersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.read(ordersRepositoryProvider).getMyOrders();
});

class MyOrdersScreen extends ConsumerWidget {
  const MyOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(myOrdersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Mes commandes',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            onPressed: () => ref.invalidate(myOrdersProvider),
          ),
        ],
      ),
      body: ordersAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (err, stack) => _ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(myOrdersProvider),
        ),
        data: (orders) {
          if (orders.isEmpty) {
            return const _EmptyView();
          }
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async => ref.invalidate(myOrdersProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: orders.length,
              separatorBuilder: (context, i) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _OrderCard(order: orders[index]),
            ),
          );
        },
      ),
    );
  }
}

// ── Carte commande ────────────────────────────────────────────────────────────
class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'UNKNOWN';
    final type = order['type'] as String? ?? '';
    final price = (order['price'] as num?)?.toInt() ?? 0;
    final pickup = order['pickupAddress'] as String? ?? '—';
    final delivery = order['deliveryAddress'] as String? ?? '—';
    final createdAt = _formatDate(order['createdAt'] as String?);

    final statusInfo = _statusInfo(status);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header : type + statut + prix ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: statusInfo.color.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                left: BorderSide(color: statusInfo.color, width: 3),
              ),
            ),
            child: Row(
              children: [
                Icon(_typeIcon(type), color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  _typeLabel(type),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                // Badge statut
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusInfo.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusInfo.label,
                    style: TextStyle(
                      color: statusInfo.color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$price FCFA',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // ── Adresses ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                _AddressRow(
                  icon: Icons.circle,
                  color: const Color(0xFF4CAF50),
                  label: 'Récupération',
                  address: pickup,
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 9),
                  child: Container(
                    width: 1.5,
                    height: 14,
                    color: AppColors.card,
                  ),
                ),
                _AddressRow(
                  icon: Icons.location_on,
                  color: AppColors.primary,
                  label: 'Destination',
                  address: delivery,
                ),
              ],
            ),
          ),

          // ── Footer : date ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Row(
              children: [
                const Icon(Icons.access_time,
                    size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  createdAt,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──
  IconData _typeIcon(String type) {
    return switch (type) {
      'RIDE' => Icons.directions_car_outlined,
      'DELIVERY' => Icons.inventory_2_outlined,
      _ => Icons.local_shipping_outlined,
    };
  }

  String _typeLabel(String type) {
    return switch (type) {
      'RIDE' => 'Thiak Thiak',
      'DELIVERY' => 'Livraison',
      _ => type,
    };
  }

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final months = [
        'jan', 'fév', 'mar', 'avr', 'mai', 'jun',
        'jul', 'aoû', 'sep', 'oct', 'nov', 'déc'
      ];
      return '${dt.day} ${months[dt.month - 1]}. ${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  _StatusInfo _statusInfo(String status) {
    return switch (status) {
      'PENDING' => _StatusInfo('En attente', const Color(0xFFFFB300)),
      'ACCEPTED' => _StatusInfo('Acceptée', const Color(0xFF2196F3)),
      'PICKED_UP' => _StatusInfo('En route', const Color(0xFF9C27B0)),
      'DELIVERED' => _StatusInfo('Livrée', const Color(0xFF4CAF50)),
      'CANCELLED' => _StatusInfo('Annulée', const Color(0xFFFF5252)),
      'PAYMENT_CONFIRMED' => _StatusInfo('Payée', const Color(0xFF00BCD4)),
      _ => _StatusInfo(status, AppColors.textSecondary),
    };
  }
}

class _StatusInfo {
  final String label;
  final Color color;
  const _StatusInfo(this.label, this.color);
}

// ── Ligne adresse ─────────────────────────────────────────────────────────────
class _AddressRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String address;

  const _AddressRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 12),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                address,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── État vide ─────────────────────────────────────────────────────────────────
class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: AppColors.card,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: AppColors.primary,
              size: 44,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Aucune commande',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Votre historique apparaîtra ici\naprès votre première commande.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ── État erreur ───────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, color: AppColors.textSecondary, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Erreur de chargement',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
