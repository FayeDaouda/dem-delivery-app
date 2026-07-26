import 'package:flutter/material.dart';

import 'gradient_sheet.dart';
import 'payment_operator_badge.dart';

/// Demande "Wave ou Orange Money ?" avant de lancer un paiement SamirPay —
/// un seul opérateur peut être demandé par appel (voir samirpay.service.js),
/// donc le choix doit se faire avant, pas après. Retourne 'WAVE',
/// 'ORANGE_MONEY', ou null si l'utilisateur annule.
Future<String?> chooseOperator(BuildContext context, {String title = 'Payer avec'}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => GradientSheet(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewPadding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetDragHandle(),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          _OperatorRow(operatorName: 'ORANGE_MONEY', onTap: () => Navigator.of(ctx).pop('ORANGE_MONEY')),
          const SizedBox(height: 10),
          _OperatorRow(operatorName: 'WAVE', onTap: () => Navigator.of(ctx).pop('WAVE')),
        ],
      ),
    ),
  );
}

class _OperatorRow extends StatelessWidget {
  final String operatorName;
  final VoidCallback onTap;
  const _OperatorRow({required this.operatorName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = PaymentOperatorBadge.colorFor(operatorName);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.40)),
        ),
        child: Row(children: [
          PaymentOperatorBadge(operatorName: operatorName, size: 30),
          const SizedBox(width: 12),
          Text(PaymentOperatorBadge.labelFor(operatorName),
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
