import '../../core/error/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../features/deliveries/providers/orders_provider.dart';

// ── Provider historique client ────────────────────────────────────────────────
final myOrdersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.read(ordersRepositoryProvider).getMyOrders();
});

// ── Filtres statuts ───────────────────────────────────────────────────────────
const _statusFilters = [
  {'key': 'all',       'label': 'Toutes'},
  {'key': 'DELIVERED', 'label': 'Livrées'},
  {'key': 'CANCELLED', 'label': 'Annulées'},
  {'key': 'PENDING',   'label': 'En attente'},
];

// ── Filtres période ───────────────────────────────────────────────────────────
const _periodFilters = [
  {'key': 'all',   'label': 'Tout'},
  {'key': 'today', 'label': "Aujourd'hui"},
  {'key': 'week',  'label': 'Cette semaine'},
  {'key': 'month', 'label': 'Ce mois'},
];

const _statusLabel = {
  'PENDING':           'En attente',
  'ACCEPTED':          'Acceptée',
  'PICKED_UP':         'En route',
  'IN_TRANSIT':        'En cours',
  'DELIVERED':         'Livrée',
  'CANCELLED':         'Annulée',
  'PAYMENT_CONFIRMED': 'Payée',
};

const _statusColor = {
  'PENDING':           Color(0xFFFFB300),
  'ACCEPTED':          Color(0xFF6366F1),
  'PICKED_UP':         Color(0xFF9C27B0),
  'IN_TRANSIT':        Color(0xFF6366F1),
  'DELIVERED':         Color(0xFF22C55E),
  'CANCELLED':         Color(0xFFEF4444),
  'PAYMENT_CONFIRMED': Color(0xFF00BCD4),
};

// ── Écran ─────────────────────────────────────────────────────────────────────
class OrdersHistoryScreen extends ConsumerStatefulWidget {
  const OrdersHistoryScreen({super.key});

  @override
  ConsumerState<OrdersHistoryScreen> createState() => _State();
}

class _State extends ConsumerState<OrdersHistoryScreen> {
  String _statusFilter = 'all';
  String _periodFilter = 'all';

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> orders) {
    var result = orders;

    if (_statusFilter != 'all') {
      result = result.where((o) =>
        (o['status'] as String? ?? '').toUpperCase() == _statusFilter
      ).toList();
    }

    if (_periodFilter != 'all') {
      final now = DateTime.now();
      result = result.where((o) {
        final raw = o['createdAt'] as String?;
        if (raw == null) return false;
        final dt = DateTime.tryParse(raw)?.toLocal();
        if (dt == null) return false;
        switch (_periodFilter) {
          case 'today':
            return dt.year == now.year && dt.month == now.month && dt.day == now.day;
          case 'week':
            final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
            final start = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
            return dt.isAfter(start);
          case 'month':
            return dt.year == now.year && dt.month == now.month;
          default:
            return true;
        }
      }).toList();
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myOrdersProvider);

    return Scaffold(
      body: Column(
        children: [
          // ── Header gradient ──
          Container(
            decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_ios_new,
                              color: Colors.white, size: 20),
                        ),
                        const Spacer(),
                        const Text('Mes commandes',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        IconButton(
                          onPressed: () => ref.invalidate(myOrdersProvider),
                          icon: const Icon(Icons.refresh,
                              color: Colors.white, size: 20),
                        ),
                      ],
                    ),
                  ),
                  async.whenOrNull(
                    data: (orders) {
                      final filtered = _applyFilters(orders);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Text(
                          '${filtered.length} commande${filtered.length != 1 ? 's' : ''}',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 13),
                        ),
                      );
                    },
                  ) ?? const SizedBox(height: 14),
                ],
              ),
            ),
          ),

          // ── Filtres statut ──
          Container(
            color: const Color(0xFFF4F6FA),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _statusFilters.map((f) {
                  final active = _statusFilter == f['key'];
                  return GestureDetector(
                    onTap: () => setState(() => _statusFilter = f['key']!),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8, bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: active ? AppColors.primary : const Color(0xFFEEF0F5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: active ? AppColors.primary : Colors.transparent),
                      ),
                      child: Text(
                        f['label']!,
                        style: TextStyle(
                          color: active ? Colors.white : const Color(0xFF7B8CA0),
                          fontSize: 13,
                          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // ── Filtres période ──
          Container(
            color: const Color(0xFFF4F6FA),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _periodFilters.map((f) {
                  final active = _periodFilter == f['key'];
                  return GestureDetector(
                    onTap: () => setState(() => _periodFilter = f['key']!),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8, bottom: 4),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: active
                              ? AppColors.primary.withValues(alpha: 0.6)
                              : const Color(0xFFDDE3EC),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 11,
                            color: active
                                ? AppColors.primary
                                : const Color(0xFF7B8CA0),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            f['label']!,
                            style: TextStyle(
                              color: active
                                  ? AppColors.primary
                                  : const Color(0xFF7B8CA0),
                              fontSize: 12,
                              fontWeight:
                                  active ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // ── Liste ──
          Expanded(
            child: Container(
              color: const Color(0xFFF4F6FA),
              child: async.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_outlined,
                          color: Color(0xFF7B8CA0), size: 48),
                      const SizedBox(height: 12),
                      Text(friendlyError(e),
                          style: const TextStyle(
                              color: Color(0xFF7B8CA0), fontSize: 13),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => ref.invalidate(myOrdersProvider),
                        child: const Text('Réessayer',
                            style: TextStyle(color: AppColors.primary)),
                      ),
                    ],
                  ),
                ),
                data: (orders) {
                  final filtered = _applyFilters(orders);
                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.receipt_long_outlined,
                              color: Color(0xFFBCC5D0), size: 64),
                          const SizedBox(height: 12),
                          const Text('Aucune commande trouvée',
                              style: TextStyle(
                                  color: Color(0xFF7B8CA0), fontSize: 15)),
                        ],
                      ),
                    );
                  }
                  return RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () async => ref.invalidate(myOrdersProvider),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => _OrderCard(order: filtered[i]),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Statuts actifs / en attente ───────────────────────────────────────────────
const _activeStatuses  = {'ACCEPTED', 'PICKED_UP', 'IN_TRANSIT'};

// ── Carte commande ────────────────────────────────────────────────────────────
class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  const _OrderCard({required this.order});

  void _onTap(BuildContext context, String status) {
    if (status == 'PENDING') {
      context.push('/orders/confirmation', extra: order);
      return;
    }
    if (_activeStatuses.contains(status)) {
      final driverId = (order['driver'] as Map?)?['id'] as String?
          ?? order['driverId'] as String?;
      if (driverId == null) return;
      context.push('/orders/tracking', extra: {
        'orderId': order['id'] as String,
        'driverId': driverId,
        'initialOrder': order,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final id       = (order['id'] as String? ?? '').toUpperCase();
    final shortId  = id.length >= 8 ? id.substring(0, 8) : id;
    final price    = (order['price'] as num?)?.toInt() ?? 0;
    final status   = (order['status'] as String? ?? '').toUpperCase();
    final rawDate  = order['createdAt'] as String?;
    final date     = rawDate != null ? _formatDate(DateTime.tryParse(rawDate)) : '—';
    final pickup   = order['pickupAddress'] as String? ?? '—';
    final delivery = order['deliveryAddress'] as String? ?? '—';
    final type     = (order['orderType'] as String?) ?? (order['type'] as String?) ?? '';
    final color    = _statusColor[status] ?? const Color(0xFF7B8CA0);
    final label    = _statusLabel[status] ?? status;

    final tappable = status == 'PENDING' || _activeStatuses.contains(status);

    return GestureDetector(
      onTap: tappable ? () => _onTap(context, status) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: tappable
              ? Border.all(color: color.withValues(alpha: 0.35), width: 1.2)
              : null,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_typeIcon(type), color: AppColors.primary, size: 16),
                  const SizedBox(width: 6),
                  Text('# $shortId',
                      style: const TextStyle(
                        color: Color(0xFF1A1A2E),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      )),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(label,
                        style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _AddrLine(icon: Icons.circle, color: const Color(0xFF22C55E), text: pickup),
              const SizedBox(height: 4),
              _AddrLine(icon: Icons.location_on, color: AppColors.primary, text: delivery),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.access_time, color: Color(0xFF7B8CA0), size: 13),
                  const SizedBox(width: 4),
                  Text(date, style: const TextStyle(color: Color(0xFF7B8CA0), fontSize: 12)),
                  const Spacer(),
                  if (tappable)
                    Row(
                      children: [
                        Text(
                          status == 'PENDING' ? 'Voir →' : 'Suivre →',
                          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  Text('$price FCFA',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _typeIcon(String type) => switch (type) {
    'RIDE' => Icons.two_wheeler,
    _ => Icons.motorcycle,
  };

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year}  '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _AddrLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _AddrLine({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 10),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
