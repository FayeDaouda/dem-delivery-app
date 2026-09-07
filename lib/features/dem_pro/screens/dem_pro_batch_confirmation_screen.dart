import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_startup_notifier.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';
import '../../../core/utils/price_format.dart';
import '../../../shared/widgets/staggered_entrance.dart';
import '../widgets/dem_pro_button.dart';

class DemProBatchConfirmationScreen extends StatelessWidget {
  final Map<String, dynamic> batch;
  const DemProBatchConfirmationScreen({super.key, required this.batch});

  @override
  Widget build(BuildContext context) {
    final orders =
        (batch['orders'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    // batchChargeFor ajoute demFee — jamais totalPrice seul.
    final total = batchChargeFor(batch);
    final scheduled = batch['scheduledAt'] as String?;
    final isScheduled = scheduled != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),

                // Icône
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.elasticOut,
                  builder: (_, v, child) =>
                      Transform.scale(scale: v.clamp(0.0, 1.15), child: child),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isScheduled ? Icons.schedule : Icons.check_circle,
                      color: AppColors.successBright,
                      size: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  isScheduled ? 'Tournée programmée !' : 'Tournée lancée !',
                  style: ClientText.headline.copyWith(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isScheduled
                      ? 'Votre tournée sera dispatchée au créneau choisi.'
                      : 'Nous recherchons un livreur pour votre tournée.',
                  textAlign: TextAlign.center,
                  style: ClientText.body.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 28),

                // Résumé
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
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
                          const Icon(
                            Icons.route_outlined,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${orders.length} arrêt${orders.length > 1 ? 's' : ''}',
                            style: ClientText.subtitle.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            formatFcfa(total),
                            style: ClientText.title.copyWith(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (isScheduled) ...[
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.schedule_outlined,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _fmtDateTime(scheduled),
                                style: ClientText.bodyStrong.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      ...orders.asMap().entries.map((e) {
                        final i = e.key;
                        final o = e.value;
                        return StaggeredEntrance(
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 10,
                                  backgroundColor: Colors.white.withValues(
                                    alpha: 0.2,
                                  ),
                                  child: Text(
                                    '${i + 1}',
                                    style: ClientText.micro.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        o['deliveryAddress'] as String? ??
                                            'Destination',
                                        style: ClientText.label.copyWith(
                                          color: Colors.white,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (o['receiverName'] != null)
                                        Text(
                                          o['receiverName'] as String,
                                          style: ClientText.label.copyWith(
                                            color: Colors.white.withValues(
                                              alpha: 0.7,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
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
                        extra: {
                          'batchId': batch['id'] as String,
                          'initialBatch': batch,
                        },
                      ),
                    ),
                  ),

                // Bouton retour home — en secondaire (à côté de "Voir le
                // suivi") il est en contour, sur fond dégradé donc en blanc
                // plutôt qu'en primary (sinon invisible) ; seul bouton
                // (tournée programmée) il reste plein en primary, comme
                // n'importe quel CTA plein sur ce dégradé.
                DemProButton(
                  label: 'Retour au tableau de bord',
                  outlined: !isScheduled,
                  color: isScheduled ? AppColors.primary : Colors.white,
                  onTap: () => context.go(appStartupNotifier.homeForRole),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fmtDateTime(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    const months = [
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
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year} à $h:$m';
  }
}
