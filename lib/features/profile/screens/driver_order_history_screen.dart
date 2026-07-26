import 'dart:convert';
import '../../../core/error/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';
import '../../../core/utils/price_format.dart';
import '../../../shared/widgets/payment_collection_dialog.dart';

const _kPageSize = 30;


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
  'PENDING':    'En attente',
  'ACCEPTED':   'Acceptée',
  'PICKED_UP':  'Récupérée',
  'IN_TRANSIT': 'En cours',
  'DELIVERED':  'Livrée',
  'CANCELLED':  'Annulée',
};

const _statusColor = {
  'PENDING':    AppColors.pending,
  'ACCEPTED':   AppColors.accentIndigo,
  'PICKED_UP':  AppColors.accentIndigo,
  'IN_TRANSIT': AppColors.accentIndigo,
  'DELIVERED':  AppColors.successLight,
  'CANCELLED':  AppColors.error,
};

// ── Récupère une page de l'historique. Le backend pagine déjà nativement
// (/orders/my?page=&limit=, réponse { orders, total, page, totalPages }) —
// on garde un repli sur l'ancien format liste brute par prudence.
Future<({List<Map<String, dynamic>> orders, bool hasMore})> _fetchOrdersPage(int page) async {
  final res = await ApiClient.dio.get('/orders/my', queryParameters: {
    'page': page,
    'limit': _kPageSize,
  });
  final raw = res.data;
  if (raw is Map) {
    final list = (raw['orders'] as List?) ?? const [];
    final currentPage = (raw['page'] as num?)?.toInt();
    final totalPages  = (raw['totalPages'] as num?)?.toInt();
    final hasMore = currentPage != null && totalPages != null && currentPage < totalPages;
    return (orders: List<Map<String, dynamic>>.from(list), hasMore: hasMore);
  }
  final list = raw is List ? raw : (raw is String ? jsonDecode(raw) as List : const []);
  return (orders: List<Map<String, dynamic>>.from(list), hasMore: false);
}

// ── Écran ─────────────────────────────────────────────────────────────────────
class DriverOrderHistoryScreen extends ConsumerStatefulWidget {
  const DriverOrderHistoryScreen({super.key});
  @override
  ConsumerState<DriverOrderHistoryScreen> createState() => _State();
}

class _State extends ConsumerState<DriverOrderHistoryScreen> {
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
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() { _initialLoading = true; _error = null; _page = 1; });
    try {
      final result = await _fetchOrdersPage(1);
      if (!mounted) return;
      setState(() {
        _orders = result.orders;
        _hasMore = result.hasMore;
        _initialLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _initialLoading = false; _error = friendlyError(e); });
    }
  }

  // Mise à jour locale après encaissement réussi — évite un rechargement
  // complet de la liste juste pour faire disparaître le badge "Non payée".
  void _onOrderPaid(String? orderId) {
    if (orderId == null || !mounted) return;
    setState(() {
      _orders = _orders.map((o) {
        if (o['id'] != orderId) return o;
        return {...o, 'paymentStatus': 'PAID'};
      }).toList();
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    try {
      final result = await _fetchOrdersPage(nextPage);
      if (!mounted) return;
      setState(() {
        _orders = [..._orders, ...result.orders];
        _hasMore = result.hasMore;
        _page = nextPage;
        _loadingMore = false;
      });
    } catch (_) {
      // Best-effort — l'utilisateur peut re-scroller pour réessayer.
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  List<Map<String, dynamic>> _applyFilters(List<Map<String, dynamic>> orders) {
    var result = orders;

    // Filtre statut
    if (_statusFilter != 'all') {
      result = result.where((o) =>
        (o['status'] as String? ?? '').toUpperCase() == _statusFilter
      ).toList();
    }

    // Filtre période
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
    final filtered = _applyFilters(_orders);

    return Scaffold(
      backgroundColor: AppColors.lightBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                        ),
                        const Spacer(),
                        Text('Historique des courses',
                            style: ClientText.subtitle.copyWith(color: Colors.white)),
                        const Spacer(),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  if (!_initialLoading && _error == null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        '${filtered.length} course${filtered.length != 1 ? 's' : ''}'
                        '${_hasMore ? '+' : ''}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13),
                      ),
                    )
                  else
                    const SizedBox(height: 14),
                ],
              ),
            ),
          ),

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
                    onTap: () => setState(() => _statusFilter = f['key']!),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8, bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: active ? AppColors.primary : AppColors.lightBorder,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: active ? AppColors.primary : Colors.transparent),
                      ),
                      child: Text(
                        f['label']!,
                        style: TextStyle(
                          color: active ? Colors.white : AppColors.textMuted,
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
            color: AppColors.lightBg,
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
                            color: active ? AppColors.primary : AppColors.textMuted,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            f['label']!,
                            style: TextStyle(
                              color: active ? AppColors.primary : AppColors.textMuted,
                              fontSize: 12,
                              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
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
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    )
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.wifi_off_outlined, color: AppColors.textMuted, size: 48),
                              const SizedBox(height: 12),
                              Text(_error!,
                                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: _loadInitial,
                                child: const Text('Réessayer', style: TextStyle(color: AppColors.primary)),
                              ),
                            ],
                          ),
                        )
                      : filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.history,
                                      color: AppColors.lightIconMuted, size: 64),
                                  const SizedBox(height: 12),
                                  const Text('Aucune course trouvée',
                                      style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
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
                                          width: 22, height: 22,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                        ),
                                      ),
                                    );
                                  }
                                  final order = filtered[i];
                                  return _OrderCard(
                                    order: order,
                                    onPaid: () => _onOrderPaid(order['id'] as String?),
                                  );
                                },
                              ),
                            ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Carte course ──────────────────────────────────────────────────────────────
class _OrderCard extends ConsumerWidget {
  final Map<String, dynamic> order;
  final VoidCallback onPaid;
  const _OrderCard({required this.order, required this.onPaid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderId  = order['id'] as String?;
    final id       = (orderId ?? '').toUpperCase();
    final shortId  = id.length >= 8 ? id.substring(0, 8) : id;
    final price    = (order['price'] as num?)?.toInt() ?? 0;
    final status   = (order['status'] as String? ?? '').toUpperCase();
    final paymentStatus = (order['paymentStatus'] as String? ?? '').toUpperCase();
    // Livrée mais jamais réglée (driver parti sans conclure le paiement) —
    // seul cas où on propose d'encaisser depuis l'historique.
    final isUnpaid = status == 'DELIVERED' && paymentStatus == 'PENDING' && orderId != null;
    final isRide   = order['orderType'] == 'RIDE';
    final rawDate  = order['createdAt'] as String?;
    final date     = rawDate != null ? _formatDate(DateTime.tryParse(rawDate)) : '—';
    final pickup   = order['pickupAddress'] as String? ?? '—';
    final delivery = order['deliveryAddress'] as String? ?? '—';
    final color    = _statusColor[status] ?? AppColors.textMuted;
    final label    = _statusLabel[status] ?? status;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('# $shortId',
                    style: ClientText.bodyStrong.copyWith(color: AppColors.textDark, fontFamily: 'monospace')),
                const Spacer(),
                if (isUnpaid) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('Non payée',
                        style: ClientText.caption.copyWith(color: AppColors.error)),
                  ),
                  const SizedBox(width: 6),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(label,
                      style: ClientText.caption.copyWith(color: color)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _AddrLine(icon: Icons.circle, color: AppColors.successLight, text: pickup),
            const SizedBox(height: 4),
            _AddrLine(icon: Icons.location_on, color: AppColors.primary, text: delivery),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.access_time, color: AppColors.textMuted, size: 13),
                const SizedBox(width: 4),
                Text(date, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const Spacer(),
                Text('$price FCFA',
                    style: ClientText.button.copyWith(color: AppColors.primary)),
              ],
            ),
            if (isUnpaid) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => showPaymentCollectionDialog(
                    context, ref,
                    orderId: orderId,
                    price: clientChargeFor(order),
                    isRide: isRide,
                    onPaid: onPaid,
                  ),
                  icon: const Icon(Icons.payments_outlined, size: 16),
                  label: const Text('Encaisser'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year}  ${local.hour.toString().padLeft(2, '0')}:'
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
              style: const TextStyle(color: AppColors.textDark, fontSize: 12),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
