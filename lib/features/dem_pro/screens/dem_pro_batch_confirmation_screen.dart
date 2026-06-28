import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_startup_notifier.dart';
import '../theme/dem_pro_colors.dart';

class DemProBatchConfirmationScreen extends StatelessWidget {
  final Map<String, dynamic> batch;
  const DemProBatchConfirmationScreen({super.key, required this.batch});

  @override
  Widget build(BuildContext context) {
    final orders    = (batch['orders'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final total     = (batch['totalPrice'] as num?)?.toInt() ?? 0;
    final scheduled = batch['scheduledAt'] as String?;
    final isScheduled = scheduled != null;

    return Scaffold(
      backgroundColor: DemProColors.bg,
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [

          const Spacer(),

          // Icône
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: DemProColors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isScheduled ? Icons.schedule : Icons.check_circle,
              color: DemProColors.success, size: 44,
            ),
          ),
          const SizedBox(height: 20),

          Text(
            isScheduled ? 'Tournée programmée !' : 'Tournée lancée !',
            style: const TextStyle(color: DemProColors.text, fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            isScheduled
                ? 'Votre tournée sera dispatchée au créneau choisi.'
                : 'Nous recherchons un livreur pour votre tournée.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: DemProColors.muted, fontSize: 14),
          ),
          const SizedBox(height: 28),

          // Résumé
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: DemProColors.bg2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: DemProColors.bg4),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.route, color: DemProColors.accent, size: 18),
                const SizedBox(width: 8),
                Text('${orders.length} arrêt${orders.length > 1 ? 's' : ''}',
                  style: const TextStyle(color: DemProColors.text, fontSize: 14, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${_fmtFcfa(total)} FCFA',
                  style: const TextStyle(color: DemProColors.accent, fontSize: 15, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 12),
              if (isScheduled) ...[
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: DemProColors.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: DemProColors.accent.withValues(alpha: 0.25)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.schedule, color: DemProColors.accent, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      _fmtDateTime(scheduled),
                      style: const TextStyle(color: DemProColors.accent, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
              ...orders.asMap().entries.map((e) {
                final i = e.key;
                final o = e.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    CircleAvatar(radius: 10, backgroundColor: DemProColors.accent.withValues(alpha: 0.15),
                      child: Text('${i + 1}', style: const TextStyle(color: DemProColors.accent, fontSize: 10, fontWeight: FontWeight.w800))),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(o['deliveryAddress'] as String? ?? 'Destination',
                        style: const TextStyle(color: DemProColors.text, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (o['receiverName'] != null)
                        Text(o['receiverName'] as String, style: const TextStyle(color: DemProColors.muted, fontSize: 11)),
                    ])),
                  ]),
                );
              }),
            ]),
          ),

          const Spacer(),

          // Bouton suivi
          if (!isScheduled)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(width: double.infinity, height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: DemProColors.accent, borderRadius: BorderRadius.circular(14)),
                  child: Material(color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => context.pushReplacement(
                        '/dem-pro/batch/tracking',
                        extra: {'batchId': batch['id'] as String, 'initialBatch': batch},
                      ),
                      child: const Center(child: Text('Voir le suivi',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
                    ),
                  ),
                )),
            ),

          // Bouton retour home
          SizedBox(width: double.infinity, height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isScheduled ? DemProColors.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: isScheduled ? null : Border.all(color: DemProColors.accent.withValues(alpha: 0.4)),
              ),
              child: Material(color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => context.go(appStartupNotifier.homeForRole),
                  child: Center(child: Text('Retour au tableau de bord',
                    style: TextStyle(
                      color: isScheduled ? Colors.white : DemProColors.accent,
                      fontWeight: FontWeight.w700, fontSize: 15,
                    ))),
                ),
              ),
            )),
        ]),
      )),
    );
  }

  static String _fmtDateTime(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    const months = ['jan.','fév.','mars','avr.','mai','juin','juil.','août','sep.','oct.','nov.','déc.'];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year} à $h:$m';
  }

  static String _fmtFcfa(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
