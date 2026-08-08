import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_startup_notifier.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';
import '../../../core/utils/price_format.dart';
import '../widgets/dem_pro_button.dart';

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
      backgroundColor: AppColors.lightBg,
      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [

          const Spacer(),

          // Icône
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.successLight.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isScheduled ? Icons.schedule : Icons.check_circle,
              color: AppColors.successLight, size: 44,
            ),
          ),
          const SizedBox(height: 20),

          Text(
            isScheduled ? 'Tournée programmée !' : 'Tournée lancée !',
            style: ClientText.headline.copyWith(color: AppColors.textDark, fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            isScheduled
                ? 'Votre tournée sera dispatchée au créneau choisi.'
                : 'Nous recherchons un livreur pour votre tournée.',
            textAlign: TextAlign.center,
            style: ClientText.body.copyWith(color: AppColors.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 28),

          // Résumé
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.lightBorder),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.route_outlined, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Text('${orders.length} arrêt${orders.length > 1 ? 's' : ''}',
                  style: ClientText.subtitle.copyWith(color: AppColors.textDark)),
                const Spacer(),
                Text(formatFcfa(total),
                  style: ClientText.title.copyWith(color: AppColors.primary, fontSize: 15)),
              ]),
              const SizedBox(height: 12),
              if (isScheduled) ...[
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.schedule_outlined, color: AppColors.primary, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      _fmtDateTime(scheduled),
                      style: ClientText.bodyStrong.copyWith(color: AppColors.primary),
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
                    CircleAvatar(radius: 10, backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                      child: Text('${i + 1}', style: ClientText.micro.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800))),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(o['deliveryAddress'] as String? ?? 'Destination',
                        style: ClientText.label.copyWith(color: AppColors.textDark), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (o['receiverName'] != null)
                        Text(o['receiverName'] as String, style: ClientText.label.copyWith(color: AppColors.textMuted)),
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
              child: DemProButton(
                label: 'Voir le suivi',
                onTap: () => context.pushReplacement(
                  '/dem-pro/batch/tracking',
                  extra: {'batchId': batch['id'] as String, 'initialBatch': batch},
                ),
              ),
            ),

          // Bouton retour home
          DemProButton(
            label: 'Retour au tableau de bord',
            outlined: !isScheduled,
            onTap: () => context.go(appStartupNotifier.homeForRole),
          ),
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

}
