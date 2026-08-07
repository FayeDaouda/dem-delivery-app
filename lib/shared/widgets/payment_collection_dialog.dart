import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/socket_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../../core/utils/dem_toast.dart';
import '../../features/deliveries/providers/orders_provider.dart';
import 'gradient_sheet.dart';
import 'operator_picker_sheet.dart';
import 'samirpay_payment_sheet.dart';
import 'swipe_to_confirm.dart';

/// Flux "Comment le client règle-t-il ?" (Cash / Mobile Money), en feuille de
/// bas d'écran — cohérent avec le reste des feuilles de paiement de l'app
/// (recharge, retrait, QR SamirPay). Utilisé pour encaisser une commande
/// livrée : juste après la livraison (active_order_screen.dart) OU en
/// rattrapage plus tard si le livreur avait quitté l'écran sans conclure
/// (badge "Non payée" dans l'historique, bannière sur l'accueil).
///
/// [onPaid] est appelé une fois le paiement confirmé (cash ou en ligne) — à
/// l'appelant de rafraîchir sa liste/son état et/ou naviguer.
/// [onDispute] est optionnel : n'affiche "Signaler un problème" que si
/// fourni (seul active_order_screen.dart, avec sa saisie de note dédiée, le
/// propose — pas nécessaire pour un simple rattrapage depuis l'historique).
/// [simulate] : pour les commandes de démo ("dev-...") — confirme le
/// paiement cash instantanément sans appeler l'API (l'ordre n'existe pas
/// vraiment côté serveur).
Future<void> showPaymentCollectionDialog(
  BuildContext context,
  WidgetRef ref, {
  required String orderId,
  required int price,
  required VoidCallback onPaid,
  String? successMessage,
  VoidCallback? onDispute,
  bool simulate = false,
}) {
  return _showChooseModeSheet(
    context, ref,
    orderId: orderId, price: price,
    onPaid: onPaid, successMessage: successMessage, onDispute: onDispute, simulate: simulate,
  );
}

Future<void> _showChooseModeSheet(
  BuildContext context,
  WidgetRef ref, {
  required String orderId,
  required int price,
  required VoidCallback onPaid,
  String? successMessage,
  VoidCallback? onDispute,
  bool simulate = false,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => GradientSheet(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(sheetCtx).viewPadding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const SizedBox(width: 32),
            const Spacer(),
            const SheetDragHandle(),
            const Spacer(),
            _CloseButton(onTap: () => Navigator.of(sheetCtx).pop()),
          ]),
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: const Icon(Icons.payments_outlined, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 14),
          Text('Comment le client règle-t-il ?', textAlign: TextAlign.center,
              style: ClientText.title.copyWith(color: Colors.white)),
          const SizedBox(height: 4),
          Text('$price FCFA',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 22),
          _PaymentMethodCard(
            icon: Icons.payments_outlined,
            title: 'Espèces',
            subtitle: 'Le client règle en main propre',
            color: AppColors.success,
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _showCashConfirmSheet(
                context, ref,
                orderId: orderId, price: price,
                onPaid: onPaid, successMessage: successMessage, onDispute: onDispute, simulate: simulate,
              );
            },
          ),
          const SizedBox(height: 12),
          _PaymentMethodCard(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Mobile Money',
            subtitle: 'Wave ou Orange Money — QR ou lien',
            color: AppColors.primary,
            onTap: () {
              Navigator.of(sheetCtx).pop();
              _payOnline(
                context, ref,
                orderId: orderId, price: price,
                onPaid: onPaid, successMessage: successMessage, onDispute: onDispute, simulate: simulate,
              );
            },
          ),
        ],
      ),
    ),
  );
}

void _showCashConfirmSheet(
  BuildContext context,
  WidgetRef ref, {
  required String orderId,
  required int price,
  required VoidCallback onPaid,
  String? successMessage,
  VoidCallback? onDispute,
  bool simulate = false,
}) {
  bool confirming = false;
  String? errorMsg;
  Key swipeKey = UniqueKey();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (sheetCtx, setSheet) {
        void confirm() async {
          setSheet(() { confirming = true; errorMsg = null; });
          final nav = Navigator.of(sheetCtx);
          bool ok = false;
          if (simulate) {
            ok = true;
          } else {
            for (int i = 0; i < 2; i++) {
              if (i > 0) await Future.delayed(const Duration(seconds: 2));
              try {
                await ref.read(ordersRepositoryProvider).confirmPayment(orderId, 'PAID');
                ok = true;
                break;
              } catch (_) {}
            }
          }
          if (ok) {
            nav.pop();
            if (context.mounted) {
              showDemToast(context, successMessage ?? 'Livraison encaissée !');
            }
            onPaid();
          } else {
            setSheet(() {
              confirming = false;
              errorMsg = 'Erreur réseau. Réessayez ou contactez le support.';
              swipeKey = UniqueKey();
            });
          }
        }

        return PopScope(
          canPop: false,
          child: GradientSheet(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(sheetCtx).viewPadding.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SheetDragHandle(),
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: const Icon(Icons.payments_outlined, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 14),
                Text('Confirmez la réception', textAlign: TextAlign.center,
                    style: ClientText.title.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                Text('$price FCFA en espèces',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: confirming ? null : () {
                    Navigator.of(sheetCtx).pop();
                    _showChooseModeSheet(
                      context, ref,
                      orderId: orderId, price: price,
                      onPaid: onPaid, successMessage: successMessage, onDispute: onDispute, simulate: simulate,
                    );
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('‹ Changer de mode de paiement',
                      style: TextStyle(fontSize: 12.5, color: Colors.white60, decoration: TextDecoration.underline)),
                ),
                if (errorMsg != null) ...[
                  const SizedBox(height: 10),
                  Text(errorMsg!, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12), textAlign: TextAlign.center),
                ],
                const SizedBox(height: 26),
                SwipeToConfirm(
                  key: swipeKey,
                  label: 'Glissez pour confirmer la réception',
                  onConfirmed: confirm,
                  loading: confirming,
                  trackColor: AppColors.success,
                  thumbColor: Colors.white,
                  iconColor: AppColors.success,
                  labelColor: Colors.white,
                ),
                if (onDispute != null) ...[
                  const SizedBox(height: 14),
                  TextButton.icon(
                    onPressed: confirming ? null : () {
                      Navigator.of(sheetCtx).pop();
                      onDispute();
                    },
                    icon: const Icon(Icons.warning_amber_outlined, size: 16, color: AppColors.surge),
                    label: const Text('Signaler un problème', style: TextStyle(color: AppColors.surge, fontSize: 13)),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _payOnline(
  BuildContext context,
  WidgetRef ref, {
  required String orderId,
  required int price,
  required VoidCallback onPaid,
  String? successMessage,
  VoidCallback? onDispute,
  bool simulate = false,
}) async {
  final operatorName = await chooseOperator(context, title: 'Le client paie avec');
  if (operatorName == null) {
    // Choix de l'opérateur annulé — on rouvre le choix du mode de paiement
    // plutôt que de laisser le driver sans aucun dialogue à l'écran.
    if (context.mounted) {
      _showChooseModeSheet(
        context, ref,
        orderId: orderId, price: price,
        onPaid: onPaid, successMessage: successMessage, onDispute: onDispute, simulate: simulate,
      );
    }
    return;
  }
  if (!context.mounted) return;

  // Suivi local : `onSuccess` n'est appelé QUE si le paiement est confirmé
  // par le webhook — si la feuille se ferme autrement (bouton "Fermer",
  // swipe, erreur réseau), ce booléen reste false.
  var succeeded = false;

  await SamirpayPaymentSheet.show(
    context,
    amount: price,
    title: 'Paiement de la livraison',
    initPayment: () => ref.read(ordersRepositoryProvider).payOnline(orderId, operatorName),
    confirmationStream: SocketService.instance.onOrderPaymentConfirmed
        .where((event) => event['orderId'] == orderId),
    onSuccess: () {
      succeeded = true;
      showDemToast(context, successMessage ?? 'Livraison encaissée !');
      onPaid();
    },
    displayOnly: true,
  );

  // Feuille fermée sans confirmation (annulée, erreur réseau...) — on
  // rouvre le choix pour que le driver puisse réessayer ou passer en cash.
  if (!succeeded && context.mounted) {
    _showChooseModeSheet(
      context, ref,
      orderId: orderId, price: price,
      onPaid: onPaid, successMessage: successMessage, onDispute: onDispute, simulate: simulate,
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _PaymentMethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.20), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: Colors.white.withValues(alpha: 0.5), size: 14),
          ]),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
      ),
    );
  }
}
