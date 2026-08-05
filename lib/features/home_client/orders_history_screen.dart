import '../../core/error/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/socket_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../../core/utils/dem_toast.dart';
import '../../core/utils/price_format.dart';
import '../../features/deliveries/providers/orders_provider.dart';
import '../../shared/widgets/address_row.dart';
import '../../shared/widgets/operator_picker_sheet.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/samirpay_payment_sheet.dart';
import '../../shared/widgets/skeleton_loader.dart';

const _kPageSize = 30;

// ── Filtres statuts ───────────────────────────────────────────────────────────
const _statusFilters = [
  {'key': 'all', 'label': 'Toutes'},
  {'key': 'DELIVERED', 'label': 'Livrées'},
  {'key': 'CANCELLED', 'label': 'Annulées'},
  {'key': 'PENDING', 'label': 'En attente'},
];

// ── Filtres période ───────────────────────────────────────────────────────────
const _periodFilters = [
  {'key': 'all', 'label': 'Tout'},
  {'key': 'today', 'label': "Aujourd'hui"},
  {'key': 'week', 'label': 'Cette semaine'},
  {'key': 'month', 'label': 'Ce mois'},
];

const _statusLabel = {
  'PENDING': 'En attente',
  'ACCEPTED': 'Acceptée',
  'PICKED_UP': 'En route',
  'IN_TRANSIT': 'En cours',
  'DELIVERED': 'Livrée',
  'CANCELLED': 'Annulée',
  'PAYMENT_CONFIRMED': 'Payée',
};

const _statusColor = {
  'PENDING': AppColors.warning,
  'ACCEPTED': AppColors.accentIndigo,
  'PICKED_UP': Color(0xFF9C27B0),
  'IN_TRANSIT': AppColors.accentIndigo,
  'DELIVERED': AppColors.successLight,
  'CANCELLED': AppColors.error,
  'PAYMENT_CONFIRMED': AppColors.accentCyan,
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

  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _orders = [];
  int _page = 1;
  bool _hasMore = true;
  bool _initialLoading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _initialLoading = true;
      _error = null;
      _page = 1;
    });
    try {
      final result = await ref
          .read(ordersRepositoryProvider)
          .getMyOrdersPage(page: 1, limit: _kPageSize);
      if (!mounted) return;
      setState(() {
        _orders = result.orders;
        _hasMore = result.hasMore;
        _initialLoading = false;
      });
      _maybeAutoLoadForFilter();
    } catch (e) {
      if (mounted)
        setState(() {
          _initialLoading = false;
          _error = friendlyError(e);
        });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    try {
      final result = await ref
          .read(ordersRepositoryProvider)
          .getMyOrdersPage(page: nextPage, limit: _kPageSize);
      if (!mounted) return;
      setState(() {
        _orders = [..._orders, ...result.orders];
        _hasMore = result.hasMore;
        _page = nextPage;
        _loadingMore = false;
      });
      _maybeAutoLoadForFilter();
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // Le backend ne filtre pas encore par statut/période — les filtres
  // s'appliquent en local sur les pages déjà chargées. Sans ça, activer un
  // filtre peut sembler ne renvoyer "aucune commande" alors que des
  // correspondances existent juste sur une page pas encore chargée, et le
  // scroll infini ne se déclenche jamais (liste filtrée trop courte pour
  // atteindre le bas de l'écran). On charge donc la suite tant qu'un filtre
  // est actif et qu'on n'a pas assez de résultats (plafonné pour éviter de
  // paginer tout l'historique si le filtre est très restrictif).
  static const _kMaxAutoLoadPage = 10;
  void _maybeAutoLoadForFilter() {
    final hasActiveFilter = _statusFilter != 'all' || _periodFilter != 'all';
    if (!hasActiveFilter || !_hasMore || _loadingMore) return;
    if (_page >= _kMaxAutoLoadPage) return;
    if (_applyFilters(_orders).length < _kPageSize) _loadMore();
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> orders) {
    var result = orders;

    if (_statusFilter != 'all') {
      result = result
          .where(
            (o) =>
                (o['status'] as String? ?? '').toUpperCase() == _statusFilter,
          )
          .toList();
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
            return dt.year == now.year &&
                dt.month == now.month &&
                dt.day == now.day;
          case 'week':
            final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
            final start = DateTime(
              startOfWeek.year,
              startOfWeek.month,
              startOfWeek.day,
            );
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
    final filtered = _applyFilters(_orders);

    return Scaffold(
      backgroundColor: AppColors.lightBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header gradient FULL WIDTH ──
          Container(
            decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
            child: SafeArea(
              bottom: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.arrow_back_ios_new,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'Mes commandes',
                          style: ClientText.subtitle.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: _loadInitial,
                          icon: const Icon(
                            Icons.refresh,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_initialLoading && _error == null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        '${filtered.length} commande${filtered.length != 1 ? 's' : ''}'
                        '${_hasMore ? '+' : ''}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 13,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 14),
                ],
              ),
            ),
          ),

          // ── Filtres + liste pleine largeur ──
          Expanded(
            child: Column(
              children: [
                // ── Filtres statut ──
                Container(
                  color: AppColors.lightBg,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _statusFilters.map((f) {
                        final active = _statusFilter == f['key'];
                        return GestureDetector(
                          onTap: () {
                            setState(() => _statusFilter = f['key']!);
                            _maybeAutoLoadForFilter();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 8, bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppColors.primary
                                  : AppColors.lightBorder,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: active
                                    ? AppColors.primary
                                    : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              f['label']!,
                              style: TextStyle(
                                color: active
                                    ? Colors.white
                                    : AppColors.textMuted,
                                fontSize: 13,
                                fontWeight: active
                                    ? FontWeight.w600
                                    : FontWeight.w400,
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
                  color: AppColors.lightBg,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _periodFilters.map((f) {
                        final active = _periodFilter == f['key'];
                        return GestureDetector(
                          onTap: () {
                            setState(() => _periodFilter = f['key']!);
                            _maybeAutoLoadForFilter();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 8, bottom: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
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
                                      : AppColors.textMuted,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  f['label']!,
                                  style: TextStyle(
                                    color: active
                                        ? AppColors.primary
                                        : AppColors.textMuted,
                                    fontSize: 12,
                                    fontWeight: active
                                        ? FontWeight.w600
                                        : FontWeight.w400,
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
                    color: AppColors.lightBg,
                    child: _initialLoading
                        ? ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: 5,
                            itemBuilder: (_, _) => const _OrderCardSkeleton(),
                          )
                        : _error != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.wifi_off_outlined,
                                  color: AppColors.textMuted,
                                  size: 48,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _error!,
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 13,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                TextButton(
                                  onPressed: _loadInitial,
                                  child: const Text(
                                    'Réessayer',
                                    style: TextStyle(color: AppColors.primary),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.receipt_long_outlined,
                                  color: AppColors.lightIconMuted,
                                  size: 64,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Aucune commande trouvée',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            color: AppColors.primary,
                            onRefresh: _loadInitial,
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: filtered.length + (_hasMore ? 1 : 0),
                              itemBuilder: (_, i) {
                                if (i >= filtered.length) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Center(
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                return _OrderCard(
                                  order: filtered[i],
                                  onPaid: _loadInitial,
                                );
                              },
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Statuts actifs / en attente ───────────────────────────────────────────────
const _activeStatuses = {'ACCEPTED', 'PICKED_UP', 'IN_TRANSIT'};

// ── Carte commande ────────────────────────────────────────────────────────────
// ── Skeleton (chargement) — épouse la forme de _OrderCard ──────────────────
class _OrderCardSkeleton extends StatelessWidget {
  const _OrderCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SkeletonBox(width: 90, height: 13),
              const Spacer(),
              SkeletonBox(
                width: 64,
                height: 20,
                borderRadius: BorderRadius.circular(20),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const SkeletonBox(width: double.infinity, height: 11),
          const SizedBox(height: 8),
          const SkeletonBox(width: 160, height: 11),
          const SizedBox(height: 16),
          Row(
            children: [
              const SkeletonBox(width: 70, height: 10),
              const Spacer(),
              SkeletonBox(
                width: 60,
                height: 12,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;
  final VoidCallback onPaid;
  const _OrderCard({required this.order, required this.onPaid});

  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  bool _checkingPayment = false;

  void _onTap(BuildContext context, String status, String paymentStatus) {
    if (status == 'PENDING') {
      context.push('/orders/confirmation', extra: widget.order);
      return;
    }
    if (_activeStatuses.contains(status)) {
      final driverId =
          (widget.order['driver'] as Map?)?['id'] as String? ??
          widget.order['driverId'] as String?;
      if (driverId == null) return;
      context.push(
        '/orders/tracking',
        extra: {
          'orderId': widget.order['id'] as String,
          'driverId': driverId,
          'initialOrder': widget.order,
        },
      );
      return;
    }
    if (status == 'DELIVERED' && paymentStatus != 'PAID') {
      _payIfStillUnpaid();
      return;
    }
    if (status == 'DELIVERED') {
      context.push(
        '/orders/detail',
        extra: {
          'orderId': widget.order['id'] as String,
          'initialOrder': widget.order,
        },
      );
    }
  }

  // Une commande livrée peut avoir été payée entre-temps par un autre canal
  // (QR affiché par le livreur, scanné par le destinataire) sans que cette
  // liste — potentiellement chargée il y a plusieurs minutes — le sache.
  // On revérifie donc toujours l'état réel avant d'ouvrir un paiement, pour
  // ne jamais proposer de payer une commande déjà réglée (double paiement).
  // Le backend refuse de toute façon une commande déjà PAID (voir
  // samirpay.service.js:requestOrderPayment), mais autant éviter d'ouvrir la
  // feuille de paiement pour rien.
  Future<void> _payIfStillUnpaid() async {
    if (_checkingPayment) return;
    final orderId = widget.order['id'] as String?;
    if (orderId == null) return;

    setState(() => _checkingPayment = true);
    try {
      final fresh = await ref
          .read(ordersRepositoryProvider)
          .getOrderById(orderId);
      if (!mounted) return;

      if ((fresh['paymentStatus'] as String? ?? 'PENDING') == 'PAID') {
        showDemToast(context, 'Cette commande est déjà payée.');
        widget.onPaid(); // rafraîchit la liste pour refléter le vrai statut
        return;
      }

      final operatorName = await chooseOperator(context);
      if (operatorName == null || !mounted) return;

      final amount = clientChargeFor(fresh);
      await SamirpayPaymentSheet.show(
        context,
        amount: amount,
        title: 'Paiement de la course',
        initPayment: () =>
            ref.read(ordersRepositoryProvider).payOnline(orderId, operatorName),
        confirmationStream: SocketService.instance.onOrderPaymentConfirmed
            .where((event) => event['orderId'] == orderId),
        onSuccess: widget.onPaid,
      );
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _checkingPayment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final id = (order['id'] as String? ?? '').toUpperCase();
    final shortId = id.length >= 8 ? id.substring(0, 8) : id;
    final price = (order['price'] as num?)?.toInt() ?? 0;
    final status = (order['status'] as String? ?? '').toUpperCase();
    final paymentStatus = (order['paymentStatus'] as String?) ?? 'PENDING';
    final rawDate = order['createdAt'] as String?;
    final date = rawDate != null
        ? _formatDate(DateTime.tryParse(rawDate))
        : '—';
    final pickup = order['pickupAddress'] as String? ?? '—';
    final delivery = order['deliveryAddress'] as String? ?? '—';
    final type =
        (order['orderType'] as String?) ?? (order['type'] as String?) ?? '';
    final color = _statusColor[status] ?? AppColors.textMuted;
    final label = _statusLabel[status] ?? status;

    // Une commande livrée mais pas encore payée en ligne reste actionnable —
    // le client peut la régler après coup (ex: le paiement à la livraison
    // n'a pas abouti).
    final unpaidDelivered = status == 'DELIVERED' && paymentStatus != 'PAID';
    // Une commande livrée et payée reste consultable — récap + éventuelle
    // photo de preuve (voir order_detail_screen.dart), utile en cas de
    // litige bien après la livraison.
    final tappable =
        status == 'PENDING' ||
        _activeStatuses.contains(status) ||
        status == 'DELIVERED';

    return Pressable(
      onTap: tappable && !_checkingPayment
          ? () => _onTap(context, status, paymentStatus)
          : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: tappable
              ? Border.all(color: color.withValues(alpha: 0.35), width: 1.2)
              : null,
          boxShadow: AppShadows.card,
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
                  Text(
                    '# $shortId',
                    style: ClientText.bodyStrong.copyWith(
                      color: AppColors.textDark,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      label,
                      style: ClientText.caption.copyWith(color: color),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              AddressRow(
                icon: Icons.circle,
                iconColor: AppColors.successLight,
                address: pickup,
                compact: true,
              ),
              const SizedBox(height: 4),
              AddressRow(
                icon: Icons.location_on,
                iconColor: AppColors.primary,
                address: delivery,
                compact: true,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.access_time,
                    color: AppColors.textMuted,
                    size: 13,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    date,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  if (_checkingPayment)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (tappable)
                    Row(
                      children: [
                        Text(
                          status == 'PENDING'
                              ? 'Voir →'
                              : unpaidDelivered
                              ? 'Payer →'
                              : status == 'DELIVERED'
                              ? 'Détails →'
                              : 'Suivre →',
                          style: ClientText.labelStrong.copyWith(color: color),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  Text(
                    formatFcfa(price),
                    style: ClientText.button.copyWith(color: AppColors.primary),
                  ),
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
