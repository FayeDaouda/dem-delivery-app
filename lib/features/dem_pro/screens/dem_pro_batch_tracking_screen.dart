import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/router/app_startup_notifier.dart';
import '../data/dem_pro_repository.dart';
import '../theme/dem_pro_colors.dart';
import '../utils/dem_pro_format.dart';
import '../theme/dem_pro_text.dart';

// ── Helpers statut batch ──────────────────────────────────────────────────────

String _batchStatusLabel(String s) => switch (s) {
  'PENDING'     => 'En recherche de livreur',
  'ACCEPTED'    => 'Livreur assigné',
  'IN_PROGRESS' => 'En cours de livraison',
  'COMPLETED'   => 'Terminée',
  'CANCELLED'   => 'Annulée',
  'SCHEDULED'   => 'Programmée',
  _             => s,
};

Color _batchStatusColor(String s) => switch (s) {
  'PENDING'     => DemProColors.warning,
  'ACCEPTED'    => DemProColors.accent,
  'IN_PROGRESS' => DemProColors.accent,
  'COMPLETED'   => DemProColors.success,
  'CANCELLED'   => DemProColors.danger,
  'SCHEDULED'   => DemProColors.muted,
  _             => DemProColors.muted,
};

String _stopStatusLabel(String s) => switch (s) {
  'PENDING'    => 'En attente',
  'ACCEPTED'   => 'Pris en charge',
  'PICKED_UP'  => 'Récupéré',
  'IN_TRANSIT' => 'En route',
  'DELIVERED'  => 'Livré',
  'CANCELLED'  => 'Annulé',
  _            => s,
};

Color _stopStatusColor(String s) => switch (s) {
  'DELIVERED'  => DemProColors.success,
  'CANCELLED'  => DemProColors.danger,
  'IN_TRANSIT' => DemProColors.accent,
  'PICKED_UP'  => DemProColors.accent,
  _            => DemProColors.muted,
};

bool _stopDone(String s) => s == 'DELIVERED';

String _fmtDate(String? iso) {
  if (iso == null) return '';
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return '';
  const m = ['jan.','fév.','mars','avr.','mai','juin','juil.','août','sep.','oct.','nov.','déc.'];
  final h  = dt.hour.toString().padLeft(2, '0');
  final mn = dt.minute.toString().padLeft(2, '0');
  return '${dt.day} ${m[dt.month - 1]} · $h:$mn';
}

// ─────────────────────────────────────────────────────────────────────────────

class DemProBatchTrackingScreen extends StatefulWidget {
  final String batchId;
  final Map<String, dynamic>? initialBatch;
  const DemProBatchTrackingScreen({super.key, required this.batchId, this.initialBatch});

  @override
  State<DemProBatchTrackingScreen> createState() => _DemProBatchTrackingScreenState();
}

class _DemProBatchTrackingScreenState extends State<DemProBatchTrackingScreen> {
  final _repo = DemProRepository(ApiClient.dio);

  Map<String, dynamic>? _batch;
  bool _loading = true;
  bool _dark = true;
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
      if (status == null || status == 'COMPLETED' || status == 'CANCELLED') return;
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
      if (mounted) setState(() { _batch = batch; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  _T get t => _T(_dark);

  @override
  Widget build(BuildContext context) {
    final t = this.t;
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      appBar: AppBar(
        backgroundColor: t.scaffoldBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: t.text, size: 18),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Suivi de tournée',
          style: DemProText.title.copyWith(color: t.text, fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _dark ? Icons.wb_sunny_outlined : Icons.dark_mode_outlined,
              color: t.muted, size: 20,
            ),
            onPressed: () => setState(() => _dark = !_dark),
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: DemProColors.accent, size: 22),
            tooltip: 'Rafraîchir',
            onPressed: () => _load(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading && _batch == null
          ? Center(child: CircularProgressIndicator(color: DemProColors.accent))
          : _batch == null
              ? _buildError(t)
              : _buildContent(t),
    );
  }

  Widget _buildError(_T t) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, color: t.muted, size: 44),
        const SizedBox(height: 14),
        Text('Impossible de charger la tournée.',
            style: DemProText.subtitle.copyWith(color: t.text, fontSize: 15)),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _load,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: DemProColors.accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('Réessayer',
                style: DemProText.bodyStrong.copyWith(color: Colors.white)),
          ),
        ),
      ],
    ),
  );

  Widget _buildContent(_T t) {
    final batch      = _batch!;
    final status     = batch['status'] as String? ?? 'PENDING';
    final orders     = (batch['orders'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final driver     = batch['driver'] as Map<String, dynamic>?;
    final total      = (batch['totalPrice'] as num?) ?? 0;
    final pickup     = batch['pickupAddress'] as String? ?? '';
    final createdAt  = batch['createdAt'] as String?;
    final statusColor = _batchStatusColor(status);
    final deliveredCount = orders.where((o) => o['status'] == 'DELIVERED').length;
    final isActive   = status == 'ACCEPTED' || status == 'IN_PROGRESS';

    return RefreshIndicator(
      color: DemProColors.accent,
      backgroundColor: t.cardBg,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Statut global ───────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: statusColor.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _batchStatusLabel(status),
                      style: DemProText.subtitle.copyWith(color: statusColor),
                    ),
                    const Spacer(),
                    if (_loading)
                      SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: statusColor.withValues(alpha: 0.6),
                        ),
                      ),
                  ]),
                  if (isActive && orders.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    // Barre de progression
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: orders.isEmpty ? 0 : deliveredCount / orders.length,
                        backgroundColor: t.cardBg3,
                        color: DemProColors.success,
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$deliveredCount / ${orders.length} arrêts livrés',
                      style: DemProText.caption.copyWith(color: t.muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Livreur ─────────────────────────────────────────────────────
            _SectionLabel(label: 'LIVREUR', t: t),
            const SizedBox(height: 10),
            if (driver != null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: t.cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: t.border),
                ),
                child: Column(children: [
                  Row(children: [
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: DemProColors.accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          _initials(driver['name'] as String?),
                          style: DemProText.subtitle.copyWith(color: DemProColors.accent, fontWeight: FontWeight.w800),
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
                            style: DemProText.subtitle.copyWith(color: t.text),
                          ),
                          Text('Moto · DEM',
                              style: DemProText.caption.copyWith(color: t.muted)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: DemProColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.check_circle, color: DemProColors.success, size: 13),
                        const SizedBox(width: 4),
                        Text('Assigné',
                            style: DemProText.caption.copyWith(color: DemProColors.success, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ]),
                  if (driver['phone'] != null) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _ContactChip(
                        icon: Icons.chat_bubble_outline,
                        label: 'WhatsApp',
                        onTap: () {
                          final phone = (driver['phone'] as String).replaceAll(RegExp(r'[^0-9]'), '');
                          final number = phone.startsWith('221') ? phone : '221$phone';
                          launchUrl(Uri.parse('https://wa.me/$number'), mode: LaunchMode.externalApplication);
                        },
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: _ContactChip(
                        icon: Icons.phone_outlined,
                        label: 'Appeler',
                        onTap: () => launchUrl(Uri.parse('tel:${driver['phone']}')),
                      )),
                    ]),
                  ],
                ]),
              )
            else
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: DemProColors.warning.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: DemProColors.warning.withValues(alpha: 0.2)),
                ),
                child: Row(children: [
                  SizedBox(
                    width: 42, height: 42,
                    child: Stack(alignment: Alignment.center, children: [
                      SizedBox(
                        width: 42, height: 42,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: DemProColors.warning.withValues(alpha: 0.5),
                        ),
                      ),
                      const Icon(Icons.two_wheeler, color: DemProColors.warning, size: 20),
                    ]),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Recherche en cours…',
                        style: DemProText.subtitle.copyWith(color: t.text)),
                      const SizedBox(height: 2),
                      Text('Nous cherchons le livreur le plus proche pour votre tournée.',
                        style: DemProText.caption.copyWith(color: t.muted)),
                    ]),
                  ),
                ]),
              ),
            const SizedBox(height: 20),

            // ── Récupération ────────────────────────────────────────────────
            _SectionLabel(label: 'RÉCUPÉRATION', t: t),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: t.cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.border),
              ),
              child: Row(children: [
                const Icon(Icons.radio_button_on, color: DemProColors.accent, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    pickup,
                    style: DemProText.body.copyWith(color: t.text),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),

            // ── Arrêts ──────────────────────────────────────────────────────
            Row(children: [
              _SectionLabel(label: 'ARRÊTS', t: t),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: DemProColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${orders.length}',
                  style: DemProText.caption.copyWith(color: DemProColors.accent, fontWeight: FontWeight.w700),
                ),
              ),
            ]),
            const SizedBox(height: 10),

            Container(
              decoration: BoxDecoration(
                color: t.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.border),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < orders.length; i++)
                    _StopRow(
                      index: i,
                      order: orders[i],
                      isLast: i == orders.length - 1,
                      t: t,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Récapitulatif ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: t.cardBg2,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Coût total', style: DemProText.caption.copyWith(color: t.muted)),
                  const SizedBox(height: 4),
                  Text(
                    DemProFormat.fcfa(total),
                    style: DemProText.headline.copyWith(color: t.text, fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ]),
                const Spacer(),
                if (createdAt != null)
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('Créée le', style: DemProText.caption.copyWith(color: t.muted)),
                    const SizedBox(height: 4),
                    Text(
                      _fmtDate(createdAt),
                      style: DemProText.caption.copyWith(color: t.muted),
                    ),
                  ]),
              ]),
            ),

            // ── Bouton retour (tournée terminée / annulée) ─────────────────
            if (status == 'COMPLETED' || status == 'CANCELLED') ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/dem-pro/batch/create', extra: batch),
                  icon: const Icon(Icons.replay, size: 18),
                  label: const Text('Recommander cette tournée', style: DemProText.subtitle),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DemProColors.accent,
                    side: const BorderSide(color: DemProColors.accent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                  label: const Text('Retour au tableau de bord', style: DemProText.subtitle),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DemProColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
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
  final _T t;
  const _StopRow({
    required this.index,
    required this.order,
    required this.isLast,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final status      = order['status'] as String? ?? 'PENDING';
    final address     = order['deliveryAddress'] as String? ?? '';
    final receiver    = order['receiverName'] as String?;
    final price       = (order['price'] as num?) ?? 0;
    final done        = _stopDone(status);
    final stopColor   = _stopStatusColor(status);
    final stopLabel   = _stopStatusLabel(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: t.border, width: 0.8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Numéro
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: done
                  ? DemProColors.success.withValues(alpha: 0.15)
                  : DemProColors.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: done
                  ? const Icon(Icons.check, color: DemProColors.success, size: 14)
                  : Text(
                      '${index + 1}',
                      style: DemProText.caption.copyWith(color: t.muted, fontWeight: FontWeight.w800),
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
                  style: DemProText.bodyStrong.copyWith(color: t.text, decoration: done ? TextDecoration.lineThrough : null, decorationColor: t.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (receiver != null && receiver.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(receiver, style: DemProText.caption.copyWith(color: t.muted)),
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
                  style: DemProText.micro.copyWith(color: stopColor),
                ),
              ),
              if (price > 0) ...[
                const SizedBox(height: 4),
                Text(
                  DemProFormat.fcfa(price),
                  style: DemProText.caption.copyWith(color: t.muted),
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
  final _T t;
  const _SectionLabel({required this.label, required this.t});

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: DemProText.caption.copyWith(color: t.muted, fontWeight: FontWeight.w700, letterSpacing: 1),
  );
}

class _ContactChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ContactChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: DemProColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DemProColors.accent.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: DemProColors.accent, size: 16),
        const SizedBox(width: 6),
        Text(label, style: DemProText.bodyStrong.copyWith(color: DemProColors.accent)),
      ]),
    ),
  );
}

// ── Palette thème (calque DemProHomeScreen) ───────────────────────────────────

class _T {
  final bool dark;
  const _T(this.dark);

  Color get scaffoldBg => dark ? DemProColors.bg    : DemProColors.lightBg;
  Color get cardBg     => dark ? DemProColors.bg2   : Colors.white;
  Color get cardBg2    => dark ? DemProColors.bg3   : DemProColors.lightCardBg2;
  Color get cardBg3    => dark ? DemProColors.bg4   : DemProColors.lightCardBg3;
  Color get border     => dark ? DemProColors.bg3   : DemProColors.lightBorder;
  Color get text       => dark ? DemProColors.text  : DemProColors.lightText;
  Color get muted      => dark ? DemProColors.muted : DemProColors.lightMuted;
}
