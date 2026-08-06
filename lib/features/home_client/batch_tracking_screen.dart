import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/error/app_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../../core/utils/dem_toast.dart';
import '../../core/utils/price_format.dart';
import '../../shared/widgets/driver_rating_dialog.dart';
import '../../shared/widgets/pressable.dart';
import '../deliveries/data/orders_repository.dart';

const _kBatchAccent = Color(0xFF0C7A5C);

const _statusLabel = {
  'PENDING': 'Recherche d\'un livreur…',
  'SCHEDULED': 'Programmée',
  'ACCEPTED': 'Livreur en route',
  'IN_PROGRESS': 'En cours',
  'COMPLETED': 'Terminée',
  'CANCELLED': 'Annulée',
};
const _statusColor = {
  'PENDING': AppColors.warning,
  'SCHEDULED': AppColors.textSecondary,
  'ACCEPTED': _kBatchAccent,
  'IN_PROGRESS': _kBatchAccent,
  'COMPLETED': AppColors.success,
  'CANCELLED': AppColors.error,
};

// ── Liste : "Mes tournées" ───────────────────────────────────────────────────
class BatchListScreen extends StatefulWidget {
  const BatchListScreen({super.key});

  @override
  State<BatchListScreen> createState() => _BatchListScreenState();
}

class _BatchListScreenState extends State<BatchListScreen> {
  final _repo = OrdersRepository();
  List<Map<String, dynamic>> _batches = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final batches = await _repo.getMyBatches();
      if (mounted)
        setState(() {
          _batches = batches;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = friendlyError(e);
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  Text(
                    'Mes tournées',
                    style: ClientText.subtitle.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _kBatchAccent),
                    )
                  : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : _batches.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.route_outlined,
                            color: Colors.white24,
                            size: 48,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Aucune tournée groupée pour le moment',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: _kBatchAccent,
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                        itemCount: _batches.length,
                        itemBuilder: (_, i) {
                          final b = _batches[i];
                          final status = (b['status'] as String? ?? '')
                              .toUpperCase();
                          final stops = (b['orders'] as List?) ?? [];
                          return Pressable(
                            onTap: () =>
                                context.push('/orders/batch/mine/${b['id']}'),
                            child: _buildBatchTile(b, status, stops),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchTile(Map<String, dynamic> b, String status, List stops) {
    final color = _statusColor[status] ?? AppColors.textMuted;
    final label = _statusLabel[status] ?? status;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                formatFcfa((b['totalPrice'] as num?)?.toInt() ?? 0),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            b['pickupAddress'] as String? ?? '',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '${stops.length} arrêt${stops.length > 1 ? 's' : ''}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ── Détail d'une tournée ─────────────────────────────────────────────────────
class BatchDetailScreen extends StatefulWidget {
  final String batchId;
  const BatchDetailScreen({super.key, required this.batchId});

  @override
  State<BatchDetailScreen> createState() => _BatchDetailScreenState();
}

class _BatchDetailScreenState extends State<BatchDetailScreen> {
  final _repo = OrdersRepository();
  Map<String, dynamic>? _batch;
  bool _loading = true;
  String? _error;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final batch = await _repo.getBatchById(widget.batchId);
      if (mounted)
        setState(() {
          _batch = batch;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = friendlyError(e);
          _loading = false;
        });
    }
  }

  Future<void> _cancel() async {
    if (_cancelling) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2540),
        title: const Text(
          'Annuler la tournée ?',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: const Text(
          'Cette action est définitive.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Retour'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Annuler la tournée',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _cancelling = true);
    try {
      await _repo.cancelBatch(widget.batchId);
      if (mounted) showDemToast(context, 'Tournée annulée.');
      _load();
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final batch = _batch;
    final status = (batch?['status'] as String? ?? '').toUpperCase();
    final cancellable = status == 'PENDING' || status == 'SCHEDULED';
    final driver = batch?['driver'] as Map<String, dynamic>?;
    final stops =
        (batch?['orders'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    // La tournée n'était jamais notable côté client — contrairement à une
    // course simple/Express — alors que le livreur, lui, note déjà le
    // client à la fin. On note sur le dernier arrêt (une note par tournée,
    // contrainte unique en base sur Rating.orderId).
    final lastStop = stops.isNotEmpty ? stops.last : null;
    final canRate =
        status == 'COMPLETED' &&
        driver != null &&
        lastStop != null &&
        lastStop['rating'] == null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  Text(
                    'Ma tournée',
                    style: ClientText.subtitle.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _kBatchAccent),
                    )
                  : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      color: _kBatchAccent,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (_statusColor[status] ?? AppColors.textMuted)
                                      .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _statusLabel[status] ?? status,
                              style: TextStyle(
                                color:
                                    _statusColor[status] ?? AppColors.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (driver != null) ...[
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  const CircleAvatar(
                                    backgroundColor: _kBatchAccent,
                                    child: Icon(
                                      Icons.person,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      driver['name'] as String? ?? 'Livreur',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (driver['phone'] != null)
                                    IconButton(
                                      onPressed: () => launchUrl(
                                        Uri.parse('tel:${driver['phone']}'),
                                      ),
                                      icon: const Icon(
                                        Icons.call,
                                        color: _kBatchAccent,
                                        size: 20,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          Text(
                            'Collecte',
                            style: ClientText.bodyStrong.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            batch?['pickupAddress'] as String? ?? '',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Destinations (${stops.length})',
                            style: ClientText.bodyStrong.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final stop in stops) _StopTile(stop: stop),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _kBatchAccent.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                const Text(
                                  'Total',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  formatFcfa(
                                    (batch?['totalPrice'] as num?)?.toInt() ??
                                        0,
                                  ),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (canRate) ...[
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => showDriverRatingDialog(
                                  context,
                                  orderId: lastStop['id'] as String,
                                  driverId: driver['id'] as String,
                                  amount: (batch?['totalPrice'] as num?)
                                      ?.toDouble(),
                                  onDone: _load,
                                ),
                                icon: const Icon(Icons.star_outline, size: 18),
                                label: const Text('Noter le livreur'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _kBatchAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (cancellable) ...[
                            const SizedBox(height: 20),
                            TextButton(
                              onPressed: _cancelling ? null : _cancel,
                              child: Text(
                                _cancelling
                                    ? 'Annulation…'
                                    : 'Annuler la tournée',
                                style: const TextStyle(
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopTile extends StatelessWidget {
  final Map<String, dynamic> stop;
  const _StopTile({required this.stop});

  @override
  Widget build(BuildContext context) {
    final status = (stop['status'] as String? ?? '').toUpperCase();
    final delivered = status == 'DELIVERED';
    final cancelled = status == 'CANCELLED';
    final charge = clientChargeFor(stop);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            delivered
                ? Icons.check_circle
                : cancelled
                ? Icons.cancel
                : Icons.radio_button_unchecked,
            color: delivered
                ? AppColors.success
                : cancelled
                ? AppColors.error
                : Colors.white38,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stop['deliveryAddress'] as String? ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if ((stop['receiverName'] as String?)?.isNotEmpty ?? false)
                  Text(
                    stop['receiverName'] as String,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            formatFcfa(charge),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
