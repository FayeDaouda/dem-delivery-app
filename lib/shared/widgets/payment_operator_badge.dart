import 'package:flutter/material.dart';

/// Couleurs de marque officielles — Wave #1DC8FF, Orange Money #FF7900.
class PaymentOperatorBadge extends StatelessWidget {
  final String operatorName; // 'WAVE' ou 'ORANGE_MONEY'
  final double size;
  const PaymentOperatorBadge({super.key, required this.operatorName, this.size = 28});

  static Color colorFor(String operatorName) =>
      operatorName == 'WAVE' ? const Color(0xFF1DC8FF) : const Color(0xFFFF7900);

  static String labelFor(String operatorName) =>
      operatorName == 'WAVE' ? 'Wave' : 'Orange Money';

  static String _assetFor(String operatorName) =>
      operatorName == 'WAVE' ? 'assets/logo_Wave.png' : 'assets/logo_OM.png';

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: Colors.white,
        child: Image.asset(_assetFor(operatorName), fit: BoxFit.cover),
      ),
    );
  }
}
