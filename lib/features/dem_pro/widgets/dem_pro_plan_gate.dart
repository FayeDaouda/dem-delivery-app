import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';
import '../../../core/utils/dem_toast.dart';
import '../../../core/utils/price_format.dart';
import '../../../shared/widgets/operator_picker_sheet.dart';
import '../../../shared/widgets/samirpay_payment_sheet.dart';
import '../data/dem_pro_repository.dart';

/// Vrai si [plan] correspond à un palier payant (Pro ou Business).
bool isProPlan(String? plan) => plan == 'PRO' || plan == 'BUSINESS';

/// Verrou léger : si [plan] n'est pas Pro/Business, affiche un dialogue
/// "fonctionnalité réservée" (titre/message fournis par l'appelant) avec un
/// bouton qui ouvre la feuille complète des plans, et retourne `false` — à
/// l'appelant de ne pas poursuivre son action dans ce cas. Si [plan] est
/// déjà Pro/Business, ne montre rien et retourne `true` immédiatement.
///
/// Usage :
///   if (!await requireProPlan(context, plan: monPlan, title: '...', message: '...')) return;
Future<bool> requireProPlan(
  BuildContext context, {
  required String? plan,
  required String title,
  required String message,
}) async {
  if (isProPlan(plan)) return true;

  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: AppColors.primary,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: ClientText.title.copyWith(
                color: AppColors.textDark,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: ClientText.body.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  showDemProPlanSheet(context);
                },
                icon: const Icon(Icons.workspace_premium, size: 18),
                label: const Text('Découvrir Pro'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(
                'Plus tard',
                style: ClientText.body.copyWith(color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return false;
}

/// Feuille "Plan X — débloquez avec Y" — comparatif complet des paliers +
/// achat direct via SamirPay. Appelable depuis n'importe quel écran DEM
/// Pro ; si [planData] n'est pas fourni (résultat déjà en cache d'un appel
/// à `DemProRepository.getMyPlan()`), la feuille le récupère elle-même.
Future<void> showDemProPlanSheet(
  BuildContext context, {
  Map<String, dynamic>? planData,
}) async {
  final repo = DemProRepository(ApiClient.dio);
  var data = planData;
  if (data == null) {
    try {
      data = await repo.getMyPlan();
    } catch (_) {
      return;
    }
  }
  if (!context.mounted) return;

  final planLabel = data['planLabel'] as String? ?? 'Gratuit';
  final features = (data['features'] as List?)?.cast<String>() ?? [];
  final nextTier = data['nextTier'] as String?;
  final nextTierFeatures =
      (data['nextTierFeatures'] as List?)?.cast<String>() ?? [];
  final commissionRate = data['commissionRatePercent'] as num?;
  final nextTierPrice = (data['nextTierPrice'] as num?)?.toInt();
  final nextTierLabel = switch (nextTier) {
    'PRO' => 'Pro',
    'BUSINESS' => 'Business',
    _ => null,
  };

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => Container(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(sheetCtx).viewPadding.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.lightBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.workspace_premium,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Plan $planLabel',
                  style: ClientText.title.copyWith(
                    color: AppColors.textDark,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Ce que vous avez déjà',
              style: ClientText.label.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (final f in features) _PlanFeatureRow(text: f, included: true),
            if (nextTierLabel != null) ...[
              const SizedBox(height: 18),
              Text(
                'Débloquez avec $nextTierLabel',
                style: ClientText.label.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              for (final f in nextTierFeatures)
                _PlanFeatureRow(text: f, included: false),
              if (nextTierPrice != null) ...[
                const SizedBox(height: 10),
                Text(
                  '${formatFcfa(nextTierPrice)} / mois',
                  style: ClientText.title.copyWith(
                    color: AppColors.textDark,
                    fontSize: 20,
                  ),
                ),
              ],
              if (commissionRate != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: AppColors.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Le wallet DEM Pro prélève une commission de ${commissionRate.toStringAsFixed(commissionRate % 1 == 0 ? 0 : 1)}% sur la part produit des commandes payées via le paiement intégré.',
                          style: ClientText.label.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: nextTierPrice == null
                      ? null
                      : () {
                          Navigator.pop(sheetCtx);
                          _purchaseDemProPlan(
                            context,
                            repo,
                            nextTier!,
                            nextTierPrice,
                            nextTierLabel,
                          );
                        },
                  icon: const Icon(Icons.workspace_premium, size: 18),
                  label: Text('Passer $nextTierLabel'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetCtx);
                    launchUrl(
                      Uri.parse(
                        'https://wa.me/221710064664?text=${Uri.encodeComponent('Bonjour, j\'ai une question sur le plan $nextTierLabel sur DEM Pro.')}',
                      ),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                  label: const Text('Une question ? Nous contacter'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

// Achète directement le palier via SamirPay — même mécanique que la passe
// journalière driver (chooseOperator + SamirpayPaymentSheet), le paiement
// active le plan automatiquement dès confirmation (voir samirpay.service.js).
Future<void> _purchaseDemProPlan(
  BuildContext context,
  DemProRepository repo,
  String plan,
  int amount,
  String? planLabel,
) async {
  final operatorName = await chooseOperator(context, title: 'Payer avec');
  if (operatorName == null || !context.mounted) return;

  await SamirpayPaymentSheet.show(
    context,
    amount: amount,
    title: 'Abonnement DEM Pro ${planLabel ?? plan}',
    initPayment: () async {
      final result = await repo.purchasePlan(plan, operatorName);
      return result;
    },
    confirmationStream: SocketService.instance.onWalletUpdated,
    matchesConfirmation: (event, payment) =>
        event['orderRef'] == payment['orderRef'],
    onSuccess: () {
      if (context.mounted) {
        showDemToast(context, 'Abonnement ${planLabel ?? plan} activé !');
      }
    },
  );
}

class _PlanFeatureRow extends StatelessWidget {
  final String text;
  final bool included;
  const _PlanFeatureRow({required this.text, required this.included});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          included ? Icons.check_circle : Icons.lock_outline_rounded,
          color: included ? AppColors.successLight : AppColors.primary,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: ClientText.body.copyWith(color: AppColors.textDark),
          ),
        ),
      ],
    ),
  );
}
