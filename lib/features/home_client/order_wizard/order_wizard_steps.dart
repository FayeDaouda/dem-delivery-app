import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';
import '../../../core/utils/price_format.dart';
import '../../../shared/widgets/address_row.dart';
import '../../../shared/widgets/contact_mini_field.dart';
import '../../../shared/widgets/primary_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Panneaux de chaque étape du parcours Express/Simple — transplantés quasi
// verbatim depuis l'ancien order_create_screen.dart. Publics (pas de préfixe
// `_`) car construits depuis order_wizard_controller.dart, dans un autre
// fichier — le préfixe `_` en Dart rend un nom privé au FICHIER, pas à la
// classe, donc ces 4 panneaux doivent être publics pour rester utilisables
// hors de ce fichier ; leurs sous-widgets internes (_EstimatePriceCard,
// _SurgeBadge, _PromoCodeField, _DeliveryTypeBadge) restent privés, jamais
// utilisés ailleurs que dans les panneaux ci-dessous.
// ─────────────────────────────────────────────────────────────────────────────

// Rappel du type de livraison choisi (Simple/Express) — répété en haut de
// chaque étape du tunnel pour que ce soit visible sans avoir à remonter à
// la barre du haut. Un seul widget pour éviter 4 copies divergentes.
class _DeliveryTypeBadge extends StatelessWidget {
  final String priority;
  const _DeliveryTypeBadge({required this.priority});

  @override
  Widget build(BuildContext context) {
    final isExpress = priority == 'EXPRESS';
    final color = isExpress ? AppColors.warning : AppColors.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isExpress ? Icons.bolt_rounded : Icons.inventory_2_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            isExpress
                ? 'Livraison Express'
                : 'Livraison Simple — tarif standard',
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class OrderStep0Panel extends StatelessWidget {
  final String priority;
  final bool routeComplete;
  final double? estimatedPrice;
  final double demFee;
  final double surgeMultiplier;
  final bool loadingSurge;
  final bool timedOut;
  final VoidCallback onRetry;
  final VoidCallback onNext;
  final double? distanceKm;
  final int? durationMin;
  const OrderStep0Panel({
    super.key,
    required this.priority,
    required this.routeComplete,
    required this.estimatedPrice,
    required this.demFee,
    required this.surgeMultiplier,
    required this.loadingSurge,
    required this.timedOut,
    required this.onRetry,
    required this.onNext,
    this.distanceKm,
    this.durationMin,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        // min : sans ça, ce Column (comme les 3 autres étapes) remplit
        // systématiquement toute la hauteur allouée par AnimatedSize même
        // quand son contenu est plus court — indispensable pour que le
        // panneau s'adapte au contenu réel (voir diagnostic pré-prod).
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SingleChildScrollView simple, sans Expanded — un Expanded/
          // Flexible ici empêchait AnimatedSize de détecter la vraie hauteur
          // du contenu. Le plafond de sécurité à 62% de l'écran reste géré
          // par HomeClientSheetScaffold.
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _DeliveryTypeBadge(priority: priority),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SizeTransition(
                      sizeFactor: anim,
                      alignment: Alignment.topCenter,
                      child: child,
                    ),
                  ),
                  child: routeComplete
                      ? _EstimatePriceCard(
                          key: const ValueKey('price'),
                          estimatedPrice: estimatedPrice,
                          demFee: demFee,
                          surgeMultiplier: surgeMultiplier,
                          loadingSurge: loadingSurge,
                          timedOut: timedOut,
                          onRetry: onRetry,
                          distanceKm: distanceKm,
                          durationMin: durationMin,
                        )
                      : Column(
                          key: const ValueKey('tip'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Astuce',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Appuie sur la barre de recherche pour choisir "
                              'comment renseigner tes adresses.',
                              maxLines: 3,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.70),
                                fontSize: 14,
                                fontWeight: FontWeight.normal,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Suivant — Contacts',
            trailingIcon: Icons.arrow_forward,
            onTap: routeComplete ? onNext : null,
          ),
        ],
      ),
    );
  }
}

// ─── Carte de prix estimé — réutilisée à l'étape 0 (Trajet) et à l'étape 3
// (Résumé) pour un affichage cohérent, dès que l'estimation revient.
class _EstimatePriceCard extends StatelessWidget {
  final double? estimatedPrice;
  final double demFee;
  final double? discountAmount;
  final String? promoLabel;
  final double surgeMultiplier;
  final bool loadingSurge;
  final bool timedOut;
  final VoidCallback onRetry;
  final double? distanceKm;
  final int? durationMin;

  const _EstimatePriceCard({
    super.key,
    required this.estimatedPrice,
    required this.demFee,
    this.discountAmount,
    this.promoLabel,
    required this.surgeMultiplier,
    required this.loadingSurge,
    required this.timedOut,
    required this.onRetry,
    this.distanceKm,
    this.durationMin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: loadingSurge
          ? const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            )
          : timedOut && estimatedPrice == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.wifi_off_outlined,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Impossible de calculer le prix',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: onRetry,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.40),
                      ),
                    ),
                    child: Text(
                      'Réessayer',
                      style: ClientText.body.copyWith(color: AppColors.primary),
                    ),
                  ),
                ),
              ],
            )
          : Builder(
              builder: (context) {
                final hasBreakdown = demFee > 0 || (discountAmount ?? 0) > 0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasBreakdown) ...[
                      Row(
                        children: [
                          const Icon(
                            Icons.two_wheeler_outlined,
                            color: AppColors.textSecondary,
                            size: 13,
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            'Course',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          if (surgeMultiplier > 1.0) ...[
                            _SurgeBadge(surgeMultiplier: surgeMultiplier),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            estimatedPrice != null
                                ? formatFcfa(estimatedPrice!)
                                : '—',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ] else if (estimatedPrice != null) ...[
                      Row(
                        children: [
                          if (surgeMultiplier > 1.0) ...[
                            _SurgeBadge(surgeMultiplier: surgeMultiplier),
                            const SizedBox(width: 8),
                          ],
                          const Text(
                            'Total à payer',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            formatFcfa(estimatedPrice!),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (estimatedPrice != null &&
                        distanceKm != null &&
                        durationMin != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.route_outlined,
                            color: AppColors.textSecondary,
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '≈ ${distanceKm!.toStringAsFixed(1)} km',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.schedule_outlined,
                            color: AppColors.textSecondary,
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$durationMin min',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (hasBreakdown) ...[
                      if (estimatedPrice != null && demFee > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.percent_outlined,
                              color: AppColors.textSecondary,
                              size: 13,
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'Frais DEM',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '+${formatFcfa(demFee)}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (estimatedPrice != null &&
                          discountAmount != null &&
                          discountAmount! > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              promoLabel != null
                                  ? 'Réduction ($promoLabel)'
                                  : 'Réduction',
                              style: const TextStyle(
                                color: AppColors.success,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '-${formatFcfa(discountAmount!)}',
                              style: const TextStyle(
                                color: AppColors.success,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (estimatedPrice != null) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Divider(
                            height: 1,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Row(
                          children: [
                            const Text(
                              'Total à payer',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              formatFcfa(
                                (estimatedPrice! +
                                        demFee -
                                        (discountAmount ?? 0))
                                    .clamp(0, double.infinity),
                              ),
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ],
                );
              },
            ),
    );
  }
}

// Badge "×1.5" etc. — utilisé à la fois par la ligne "Course" (ventilation
// complète) et par la ligne "Total à payer" (vue simplifiée sans frais ni
// réduction), d'où l'extraction pour ne pas dupliquer ce petit morceau.
class _SurgeBadge extends StatelessWidget {
  final double surgeMultiplier;
  const _SurgeBadge({required this.surgeMultiplier});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surge.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.surge.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.flash_on, color: AppColors.surge, size: 11),
          const SizedBox(width: 2),
          Text(
            '×${surgeMultiplier.toStringAsFixed(1)}',
            style: const TextStyle(
              color: AppColors.surge,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// Champ de saisie d'un code promo — n'affiche jamais le mot "erreur" pour un
// simple "pas de promo" (silencieux), seulement pour un code invalide.
class _PromoCodeField extends StatelessWidget {
  final TextEditingController controller;
  final String? error;
  final bool checking;
  final bool applied;
  final VoidCallback onApply;

  const _PromoCodeField({
    required this.controller,
    this.error,
    required this.checking,
    required this.applied,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Code promo (optionnel)',
                  hintStyle: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: AppColors.card,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: checking ? null : onApply,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: applied
                      ? AppColors.success.withValues(alpha: 0.15)
                      : AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (applied ? AppColors.success : AppColors.primary)
                        .withValues(alpha: 0.4),
                  ),
                ),
                child: checking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    : Text(
                        applied ? 'Appliqué ✓' : 'Appliquer',
                        style: TextStyle(
                          color: applied
                              ? AppColors.success
                              : AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            error!,
            style: const TextStyle(color: AppColors.error, fontSize: 11.5),
          ),
        ],
      ],
    );
  }
}

class OrderStep1Panel extends StatelessWidget {
  final String priority;
  final String orderType;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final VoidCallback onPickContact;
  final VoidCallback? onPickMe;
  final VoidCallback? onPhoneComplete;
  final VoidCallback onNext;

  const OrderStep1Panel({
    super.key,
    required this.priority,
    required this.orderType,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.onPickContact,
    this.onPickMe,
    this.onPhoneComplete,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Astuce : ',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.70),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Icon(
                        Icons.person_outline_rounded,
                        color: Colors.white.withValues(alpha: 0.70),
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'sélectionnez un contact pour gagner du temps',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.70),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ContactMiniField(
                  label: 'Expéditeur',
                  dotColor: AppColors.success,
                  nameCtrl: nameCtrl,
                  phoneCtrl: phoneCtrl,
                  onPick: onPickContact,
                  onPickMe: onPickMe,
                  onPhoneComplete: onPhoneComplete,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Suivant — Destinataire',
            trailingIcon: Icons.arrow_forward,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

class OrderStep2Panel extends StatelessWidget {
  final String priority;
  final String orderType;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController descriptionCtrl;
  final VoidCallback onPickContact;
  final VoidCallback? onPickMe;
  final VoidCallback? onPhoneComplete;
  final VoidCallback onNext;

  const OrderStep2Panel({
    super.key,
    required this.priority,
    required this.orderType,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.descriptionCtrl,
    required this.onPickContact,
    this.onPickMe,
    this.onPhoneComplete,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Astuce : ',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Icon(
                  Icons.person_outline_rounded,
                  color: Colors.white.withValues(alpha: 0.70),
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  'sélectionnez un contact pour gagner du temps',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ContactMiniField(
                  label: 'Destinataire',
                  dotColor: AppColors.error,
                  nameCtrl: nameCtrl,
                  phoneCtrl: phoneCtrl,
                  onPick: onPickContact,
                  onPickMe: onPickMe,
                  onPhoneComplete: onPhoneComplete,
                ),
                if (orderType == 'DELIVERY') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionCtrl,
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Description du colis (optionnel)',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 14,
                      ),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 12, right: 8),
                        child: Icon(
                          Icons.inventory_2_outlined,
                          color: Colors.white.withValues(alpha: 0.65),
                          size: 18,
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 0,
                        minHeight: 0,
                      ),
                      fillColor: Colors.white.withValues(alpha: 0.14),
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                      isDense: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Suivant — Résumé',
            trailingIcon: Icons.arrow_forward,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

class OrderStep3Panel extends StatelessWidget {
  final String priority;
  final String pickupLabel;
  final String deliveryLabel;
  final double? estimatedPrice;
  final double demFee;
  final double? discountAmount;
  final String? promoLabel;
  final TextEditingController promoCodeCtrl;
  final String? promoError;
  final bool checkingPromo;
  final VoidCallback onApplyPromo;
  final double surgeMultiplier;
  final bool loadingSurge;
  final bool timedOut;
  final bool submitting;
  final bool canSubmit;
  final VoidCallback onRetry;
  final VoidCallback onSubmit;
  final VoidCallback? onEditPickup;
  final VoidCallback? onEditDelivery;
  final double? distanceKm;
  final int? durationMin;

  const OrderStep3Panel({
    super.key,
    required this.priority,
    required this.pickupLabel,
    required this.deliveryLabel,
    required this.estimatedPrice,
    required this.demFee,
    this.discountAmount,
    this.promoLabel,
    required this.promoCodeCtrl,
    this.promoError,
    required this.checkingPromo,
    required this.onApplyPromo,
    required this.surgeMultiplier,
    required this.loadingSurge,
    required this.timedOut,
    required this.submitting,
    required this.canSubmit,
    required this.onRetry,
    required this.onSubmit,
    this.onEditPickup,
    this.onEditDelivery,
    this.distanceKm,
    this.durationMin,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: onEditPickup,
                        child: Row(
                          children: [
                            Expanded(
                              child: AddressRow(
                                icon: Icons.circle,
                                iconColor: AppColors.success,
                                address: pickupLabel,
                                dark: true,
                              ),
                            ),
                            if (onEditPickup != null)
                              Icon(
                                Icons.edit_outlined,
                                color: AppColors.textSecondary.withValues(
                                  alpha: 0.5,
                                ),
                                size: 14,
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Container(
                          width: 2,
                          height: 14,
                          color: AppColors.textSecondary.withValues(alpha: 0.3),
                        ),
                      ),
                      GestureDetector(
                        onTap: onEditDelivery,
                        child: Row(
                          children: [
                            Expanded(
                              child: AddressRow(
                                icon: Icons.location_on,
                                iconColor: AppColors.error,
                                address: deliveryLabel,
                                dark: true,
                              ),
                            ),
                            if (onEditDelivery != null)
                              Icon(
                                Icons.edit_outlined,
                                color: AppColors.textSecondary.withValues(
                                  alpha: 0.5,
                                ),
                                size: 14,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _EstimatePriceCard(
                  estimatedPrice: estimatedPrice,
                  demFee: demFee,
                  discountAmount: discountAmount,
                  promoLabel: promoLabel,
                  surgeMultiplier: surgeMultiplier,
                  loadingSurge: loadingSurge,
                  timedOut: timedOut,
                  onRetry: onRetry,
                  distanceKm: distanceKm,
                  durationMin: durationMin,
                ),
                if (estimatedPrice != null && !loadingSurge && !timedOut) ...[
                  const SizedBox(height: 8),
                  _PromoCodeField(
                    controller: promoCodeCtrl,
                    error: promoError,
                    checking: checkingPromo,
                    applied: discountAmount != null && discountAmount! > 0,
                    onApply: onApplyPromo,
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.payments_outlined,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.60),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Paiement en espèces à la livraison par défaut — le paiement en ligne sera aussi proposé une fois un livreur trouvé.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.60),
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const SizedBox(height: 8),
          PrimaryButton(
            label: 'Trouvez un livreur',
            onTap: (canSubmit && !submitting) ? onSubmit : null,
            loading: submitting,
          ),
        ],
      ),
    );
  }
}
