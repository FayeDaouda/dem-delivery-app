import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/router/app_startup_notifier.dart';
import '../../../core/utils/dem_toast.dart';
import '../../deliveries/data/orders_repository.dart';
import '../data/dem_pro_repository.dart';
import '../../../shared/widgets/staggered_entrance.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/price_format.dart';
import '../../../core/theme/client_text.dart';

// ── Helpers statut batch ──────────────────────────────────────────────────────

String _batchStatusLabel(String s) => switch (s) {
  'PENDING' => 'En recherche de livreur',
  'ACCEPTED' => 'Livreur assigné',
  'IN_PROGRESS' => 'En cours de livraison',
  'COMPLETED' => 'Terminée',
  'CANCELLED' => 'Annulée',
  'SCHEDULED' => 'Programmée',
  _ => s,
};

Color _batchStatusColor(String s) => switch (s) {
  'PENDING' => AppColors.warning,
  'ACCEPTED' => AppColors.primary,
  'IN_PROGRESS' => AppColors.primary,
  'COMPLETED' => AppColors.successLight,
  'CANCELLED' => AppColors.error,
  'SCHEDULED' => AppColors.textMuted,
  _ => AppColors.textMuted,
};

String _stopStatusLabel(String s) => switch (s) {
  'PENDING' => 'En attente',
  'ACCEPTED' => 'Pris en charge',
  'PICKED_UP' => 'Récupéré',
  'IN_TRANSIT' => 'En route',
  'DELIVERED' => 'Livré',
  'CANCELLED' => 'Annulé',
  _ => s,
};

Color _stopStatusColor(String s) => switch (s) {
  'DELIVERED' => AppColors.successLight,
  'CANCELLED' => AppColors.error,
  'IN_TRANSIT' => AppColors.primary,
  'PICKED_UP' => AppColors.primary,
  _ => AppColors.textMuted,
};

bool _stopDone(String s) => s == 'DELIVERED';

String _fmtDate(String? iso) {
  if (iso == null) return '';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return '';
  const m = [
    'jan.',
    'fév.',
    'mars',
    'avr.',
    'mai',
    'juin',
    'juil.',
    'août',
    'sep.',
    'oct.',
    'nov.',
    'déc.',
  ];
  final h = dt.hour.toString().padLeft(2, '0');
  final mn = dt.minute.toString().padLeft(2, '0');
  return '${dt.day} ${m[dt.month - 1]} · $h:$mn';
}

// ─────────────────────────────────────────────────────────────────────────────

class DemProBatchTrackingScreen extends StatefulWidget {
  final String batchId;
  final Map<String, dynamic>? initialBatch;
  const DemProBatchTrackingScreen({
    super.key,
    required this.batchId,
    this.initialBatch,
  });

  @override
  State<DemProBatchTrackingScreen> createState() =>
      _DemProBatchTrackingScreenState();
}

class _DemProBatchTrackingScreenState extends State<DemProBatchTrackingScreen> {
  final _repo = DemProRepository(ApiClient.dio);

  Map<String, dynamic>? _batch;
  bool _loading = true;
  bool _cancelling = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialBatch != null) {
      _batch = widget.initialBatch;
      _loading = false;
    }
    _load(silent: widget.initialBatch != null);
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      final status = _batch?['status'] as String?;
      if (status == null || status == 'COMPLETED' || status == 'CANCELLED')
        return;
      _load(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final batch = await _repo.getBatchById(widget.batchId);
      if (mounted)
        setState(() {
          _batch = batch;
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Annulation — l'endpoint backend existait déjà (DELETE /dem-pro/batch/:id)
  // mais rien ne l'appelait côté app, contrairement à la commande simple qui
  // propose bien "Annuler" (dem_pro_order_confirmation_screen.dart).
  Future<void> _cancelBatch() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Annuler cette tournée ?',
          style: ClientText.bodyStrong.copyWith(color: AppColors.textDark),
        ),
        content: Text(
          'Toutes les livraisons non encore effectuées de cette tournée seront annulées.',
          style: ClientText.body.copyWith(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Continuer',
              style: ClientText.body.copyWith(color: AppColors.primary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Annuler la tournée',
              style: ClientText.body.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await _repo.cancelBatch(widget.batchId);
      if (mounted) await _load(silent: true);
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  // Notation du livreur — existait déjà pour une commande DEM Pro seule
  // (dem_pro_order_tracking_screen.dart:_showCompletionDialog) mais pas pour
  // une tournée groupée. Notée sur le dernier arrêt (une note par tournée,
  // contrainte unique côté serveur) ; déclenchée par bouton (pas d'événement
  // temps réel "tournée terminée" sur cet écran, à la différence de la
  // commande seule) plutôt qu'un popup automatique.
  void _showRatingDialog(String orderId, String driverId) {
    int selectedRating = 5;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                builder: (_, v, child) =>
                    Transform.scale(scale: v.clamp(0.0, 1.15), child: child),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.successLight.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: AppColors.successLight,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Tournée terminée !',
                style: ClientText.title.copyWith(
                  color: AppColors.textDark,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Notez le livreur',
                style: ClientText.subtitle.copyWith(color: AppColors.textDark),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final star = i + 1;
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedRating = star),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        star <= selectedRating ? Icons.star : Icons.star_border,
                        color: star <= selectedRating
                            ? AppColors.ratingGold
                            : AppColors.textMuted,
                        size: 32,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await OrdersRepository().rateDriver(
                        orderId: orderId,
                        driverId: driverId,
                        score: selectedRating,
                      );
                    } catch (_) {}
                    if (mounted) _load();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Envoyer',
                    style: ClientText.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Passer',
                    style: ClientText.body.copyWith(color: AppColors.textMuted),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: AppColors.lightBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: AppColors.textDark,
            size: 18,
          ),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Suivi de tournée',
          style: ClientText.title.copyWith(
            color: AppColors.textDark,
            fontSize: 17,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AppColors.primary, size: 22),
            tooltip: 'Rafraîchir',
            onPressed: () => _load(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading && _batch == null
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _batch == null
          ? _buildError()
          : _buildContent(),
    );
  }

  Widget _buildError() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, color: AppColors.textMuted, size: 44),
        const SizedBox(height: 14),
        Text(
          'Impossible de charger la tournée.',
          style: ClientText.subtitle.copyWith(
            color: AppColors.textDark,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _load,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Réessayer',
              style: ClientText.bodyStrong.copyWith(color: Colors.white),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildContent() {
    final batch = _batch!;
    final status = batch['status'] as String? ?? 'PENDING';
    final orders =
        (batch['orders'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final driver = batch['driver'] as Map<String, dynamic>?;
    final total = (batch['totalPrice'] as num?) ?? 0;
    final pickup = batch['pickupAddress'] as String? ?? '';
    final createdAt = batch['createdAt'] as String?;
    final statusColor = _batchStatusColor(status);
    final deliveredCount = orders
        .where((o) => o['status'] == 'DELIVERED')
        .length;
    final isActive = status == 'ACCEPTED' || status == 'IN_PROGRESS';
    final lastStop = orders.isNotEmpty ? orders.last : null;
    final canRate =
        status == 'COMPLETED' &&
        driver != null &&
        lastStop != null &&
        lastStop['rating'] == null;

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: Colors.white,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Statut global ───────────────────────────────────────────────
            StaggeredEntrance(
              index: 0,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.25),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.14),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _batchStatusLabel(status),
                          style: ClientText.subtitle.copyWith(
                            color: statusColor,
                          ),
                        ),
                        const Spacer(),
                        if (_loading)
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: statusColor.withValues(alpha: 0.6),
                            ),
                          ),
                      ],
                    ),
                    if (isActive && orders.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      // Barre de progression
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: orders.isEmpty
                              ? 0
                              : deliveredCount / orders.length,
                          backgroundColor: AppColors.lightFill,
                          color: AppColors.successLight,
                          minHeight: 6,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$deliveredCount / ${orders.length} arrêts livrés',
                        style: ClientText.label.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Livreur ─────────────────────────────────────────────────────
            _SectionLabel(label: 'LIVREUR'),
            const SizedBox(height: 10),
            if (driver != null)
              StaggeredEntrance(
                index: 1,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.lightBorder),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                _initials(driver['name'] as String?),
                                style: ClientText.subtitle.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  driver['name'] as String? ?? 'Livreur DEM',
                                  style: ClientText.subtitle.copyWith(
                                    color: AppColors.textDark,
                                  ),
                                ),
                                Text(
                                  'Moto · DEM',
                                  style: ClientText.label.copyWith(
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.successLight.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check_circle,
                                  color: AppColors.successLight,
                                  size: 13,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Assigné',
                                  style: ClientText.label.copyWith(
                                    color: AppColors.successLight,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (driver['phone'] != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _ContactChip(
                                icon: Icons.chat_bubble_outline,
                                label: 'WhatsApp',
                                onTap: () {
                                  final phone = (driver['phone'] as String)
                                      .replaceAll(RegExp(r'[^0-9]'), '');
                                  final number = phone.startsWith('221')
                                      ? phone
                                      : '221$phone';
                                  launchUrl(
                                    Uri.parse('https://wa.me/$number'),
                                    mode: LaunchMode.externalApplication,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _ContactChip(
                                icon: Icons.phone_outlined,
                                label: 'Appeler',
                                onTap: () => launchUrl(
                                  Uri.parse('tel:${driver['phone']}'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else
              StaggeredEntrance(
                index: 1,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 42,
                        height: 42,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 42,
                              height: 42,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.warning.withValues(alpha: 0.5),
                              ),
                            ),
                            const Icon(
                              Icons.two_wheeler,
                              color: AppColors.warning,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recherche en cours…',
                              style: ClientText.subtitle.copyWith(
                                color: AppColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Nous cherchons le livreur le plus proche pour votre tournée.',
                              style: ClientText.label.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),

            // ── Récupération ────────────────────────────────────────────────
            _SectionLabel(label: 'RÉCUPÉRATION'),
            const SizedBox(height: 10),
            StaggeredEntrance(
              index: 2,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.lightBorder),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.radio_button_on,
                      color: AppColors.primary,
                      size: 16,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        pickup,
                        style: ClientText.body.copyWith(
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Arrêts ──────────────────────────────────────────────────────
            Row(
              children: [
                _SectionLabel(label: 'ARRÊTS'),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${orders.length}',
                    style: ClientText.label.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            StaggeredEntrance(
              index: 3,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.lightBorder),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < orders.length; i++)
                      _StopRow(
                        index: i,
                        order: orders[i],
                        isLast: i == orders.length - 1,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Récapitulatif ───────────────────────────────────────────────
            StaggeredEntrance(
              index: 4,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.lightFill,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Coût total',
                          style: ClientText.label.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatFcfa(total),
                          style: ClientText.headline.copyWith(
                            color: AppColors.textDark,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (createdAt != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Créée le',
                            style: ClientText.label.copyWith(
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _fmtDate(createdAt),
                            style: ClientText.label.copyWith(
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),

            if (canRate) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => _showRatingDialog(
                    lastStop['id'] as String,
                    driver['id'] as String,
                  ),
                  icon: const Icon(Icons.star_outline, size: 18),
                  label: Text(
                    'Noter le livreur',
                    style: ClientText.subtitle.copyWith(
                      color: AppColors.textDark,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],

            // ── Bouton retour (tournée terminée / annulée) ─────────────────
            if (status == 'COMPLETED' || status == 'CANCELLED') ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      context.push('/dem-pro/batch/create', extra: batch),
                  icon: const Icon(Icons.replay, size: 18),
                  label: Text(
                    'Recommander cette tournée',
                    style: ClientText.subtitle.copyWith(
                      color: AppColors.textDark,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => context.go(appStartupNotifier.homeForRole),
                  icon: const Icon(Icons.home_outlined, size: 20),
                  label: Text(
                    'Retour au tableau de bord',
                    style: ClientText.subtitle.copyWith(
                      color: AppColors.textDark,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _cancelling ? null : _cancelBatch,
                  icon: _cancelling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.error,
                          ),
                        )
                      : const Icon(Icons.close, size: 18),
                  label: Text(
                    'Annuler la tournée',
                    style: ClientText.subtitle.copyWith(color: AppColors.error),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _initials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final p = name.trim().split(RegExp(r'\s+'));
    return p.length >= 2
        ? '${p[0][0]}${p[1][0]}'.toUpperCase()
        : p[0][0].toUpperCase();
  }
}

// ── Stop row ──────────────────────────────────────────────────────────────────

class _StopRow extends StatelessWidget {
  final int index;
  final Map<String, dynamic> order;
  final bool isLast;
  const _StopRow({
    required this.index,
    required this.order,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'PENDING';
    final address = order['deliveryAddress'] as String? ?? '';
    final receiver = order['receiverName'] as String?;
    final price = (order['price'] as num?) ?? 0;
    final done = _stopDone(status);
    final stopColor = _stopStatusColor(status);
    final stopLabel = _stopStatusLabel(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(color: AppColors.lightBorder, width: 0.8),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Numéro
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: done
                  ? AppColors.successLight.withValues(alpha: 0.15)
                  : AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: done
                  ? const Icon(
                      Icons.check,
                      color: AppColors.successLight,
                      size: 14,
                    )
                  : Text(
                      '${index + 1}',
                      style: ClientText.label.copyWith(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  address,
                  style: ClientText.bodyStrong.copyWith(
                    color: AppColors.textDark,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: AppColors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (receiver != null && receiver.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    receiver,
                    style: ClientText.label.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: stopColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  stopLabel,
                  style: ClientText.micro.copyWith(color: stopColor),
                ),
              ),
              if (price > 0) ...[
                const SizedBox(height: 4),
                Text(
                  formatFcfa(price),
                  style: ClientText.label.copyWith(color: AppColors.textMuted),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Helpers widgets ───────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: ClientText.label.copyWith(
      color: AppColors.textMuted,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
    ),
  );
}

class _ContactChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ContactChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.primary, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: ClientText.bodyStrong.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    ),
  );
}
