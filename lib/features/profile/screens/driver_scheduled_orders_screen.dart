import 'package:flutter/material.dart';

import '../../../core/error/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';
import '../../../core/utils/dem_toast.dart';
import '../../../core/utils/price_format.dart';
import '../../deliveries/data/orders_repository.dart';

// ── Courses programmées — job board + mes réservations ────────────────────
// Deux onglets :
//  - "Disponibles" : commandes SCHEDULED pas encore réservées (visibles
//    même hors ligne, voir scheduled-dispatch.service.js côté backend).
//  - "Mes réservations" : celles que ce driver a déjà réservées, avec un
//    bouton pour se désister si besoin (relance automatiquement la
//    recherche côté serveur).
class DriverScheduledOrdersScreen extends StatefulWidget {
  const DriverScheduledOrdersScreen({super.key});

  @override
  State<DriverScheduledOrdersScreen> createState() => _DriverScheduledOrdersScreenState();
}

class _DriverScheduledOrdersScreenState extends State<DriverScheduledOrdersScreen>
    with SingleTickerProviderStateMixin {
  final _repo = OrdersRepository();
  late final TabController _tabCtrl = TabController(length: 2, vsync: this);

  List<Map<String, dynamic>>? _available;
  List<Map<String, dynamic>>? _mine;
  String? _error;
  final Set<String> _actionLoading = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([
        _repo.getAvailableScheduledOrders(),
        _repo.getMyScheduledOrders(),
      ]);
      if (!mounted) return;
      setState(() {
        _available = results[0];
        _mine = results[1];
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _claim(String id) async {
    if (_actionLoading.contains(id)) return;
    setState(() => _actionLoading.add(id));
    try {
      await _repo.claimScheduledOrder(id);
      if (!mounted) return;
      showDemToast(context, 'Course réservée — retrouvez-la dans "Mes réservations".');
      await _loadAll();
      if (mounted) _tabCtrl.animateTo(1);
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _actionLoading.remove(id));
    }
  }

  Future<void> _release(String id) async {
    if (_actionLoading.contains(id)) return;
    final confirmed = await _confirmRelease();
    if (confirmed != true) return;
    setState(() => _actionLoading.add(id));
    try {
      await _repo.releaseScheduledOrder(id);
      if (!mounted) return;
      showDemToast(context, 'Réservation annulée.');
      await _loadAll();
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _actionLoading.remove(id));
    }
  }

  Future<bool?> _confirmRelease() => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Se désister de cette course ?',
          style: TextStyle(color: AppColors.textDark, fontWeight: FontWeight.w700, fontSize: 16)),
      content: const Text(
        'Elle redevient disponible pour un autre livreur. Le client sera prévenu si la date est proche.',
        style: TextStyle(color: AppColors.textMuted),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler', style: TextStyle(color: AppColors.textMuted))),
        TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Me désister', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700))),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: AppColors.primaryMid,
        foregroundColor: Colors.white,
        title: const Text('Courses programmées'),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(text: 'Disponibles${_available != null ? ' (${_available!.length})' : ''}'),
            Tab(text: 'Mes réservations${_mine != null ? ' (${_mine!.length})' : ''}'),
          ],
        ),
      ),
      body: _error != null
          ? _ErrorState(message: _error!, onRetry: _loadAll)
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _OrderList(
                  orders: _available,
                  emptyLabel: 'Aucune course programmée disponible pour le moment.',
                  onRefresh: _loadAll,
                  cardBuilder: (o) => _ScheduledOrderCard(
                    order: o,
                    actionLabel: 'Réserver',
                    actionColor: AppColors.primary,
                    loading: _actionLoading.contains(o['id']),
                    onAction: () => _claim(o['id'] as String),
                  ),
                ),
                _OrderList(
                  orders: _mine,
                  emptyLabel: 'Vous n\'avez réservé aucune course programmée.',
                  onRefresh: _loadAll,
                  cardBuilder: (o) => _ScheduledOrderCard(
                    order: o,
                    actionLabel: 'Se désister',
                    actionColor: AppColors.error,
                    loading: _actionLoading.contains(o['id']),
                    onAction: () => _release(o['id'] as String),
                  ),
                ),
              ],
            ),
    );
  }
}

class _OrderList extends StatelessWidget {
  final List<Map<String, dynamic>>? orders;
  final String emptyLabel;
  final Future<void> Function() onRefresh;
  final Widget Function(Map<String, dynamic>) cardBuilder;
  const _OrderList({required this.orders, required this.emptyLabel, required this.onRefresh, required this.cardBuilder});

  @override
  Widget build(BuildContext context) {
    if (orders == null) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.primary,
      child: orders!.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 100),
                Icon(Icons.event_available_outlined, size: 48, color: AppColors.lightIconMuted),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(emptyLabel, textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: orders!.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: cardBuilder(orders![i]),
              ),
            ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, color: AppColors.error, size: 40),
      const SizedBox(height: 10),
      Text(message, style: const TextStyle(color: AppColors.textMuted)),
      const SizedBox(height: 14),
      TextButton(onPressed: onRetry, child: const Text('Réessayer')),
    ]),
  );
}

class _ScheduledOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final String actionLabel;
  final Color actionColor;
  final bool loading;
  final VoidCallback onAction;
  const _ScheduledOrderCard({
    required this.order, required this.actionLabel, required this.actionColor,
    required this.loading, required this.onAction,
  });

  String _fmtWhen(dynamic raw) {
    final date = DateTime.tryParse(raw as String? ?? '')?.toLocal();
    if (date == null) return '—';
    const jours = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
    final j = jours[date.weekday - 1];
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '$j ${date.day}/${date.month} à $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final price = (order['price'] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.pending.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.schedule_outlined, size: 14, color: AppColors.pending),
              const SizedBox(width: 5),
              Text(_fmtWhen(order['scheduledAt']),
                  style: const TextStyle(color: AppColors.pending, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
          const Spacer(),
          Text(formatFcfa(price), style: ClientText.bodyStrong.copyWith(color: AppColors.primaryDark)),
        ]),
        const SizedBox(height: 10),
        _addressRow(Icons.circle, AppColors.successLight, order['pickupAddress'] as String? ?? '—'),
        const SizedBox(height: 6),
        _addressRow(Icons.location_on, AppColors.error, order['deliveryAddress'] as String? ?? '—'),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: loading ? null : onAction,
            style: OutlinedButton.styleFrom(
              foregroundColor: actionColor,
              side: BorderSide(color: actionColor),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: loading
                ? SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: actionColor))
                : Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  Widget _addressRow(IconData icon, Color color, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(color: AppColors.textDark, fontSize: 13))),
    ],
  );
}
