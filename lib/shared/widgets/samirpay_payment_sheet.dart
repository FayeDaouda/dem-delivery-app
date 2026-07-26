import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/error/app_exception.dart';
import '../../core/utils/dem_toast.dart';
import 'gradient_sheet.dart';
import 'payment_operator_badge.dart';

/// Feuille de paiement SamirPay partagée — recharge du portefeuille livreur
/// ET paiement client en ligne utilisent ce même composant (montant, QR
/// code, boutons Wave/Orange Money). La confirmation arrive via un événement
/// socket (le backend confirme uniquement après vérification du webhook côté
/// serveur — voir samirpay.service.js), pas de polling ici.
class SamirpayPaymentSheet extends StatefulWidget {
  final int amount;
  final String title;
  final Future<Map<String, dynamic>> Function() initPayment;
  final Stream<Map<String, dynamic>> confirmationStream;
  final VoidCallback onSuccess;

  /// Quand quelqu'un d'autre que le porteur du téléphone va scanner le QR
  /// (ex: le livreur montre son écran à l'expéditeur ou au destinataire) —
  /// les boutons "Payer avec Wave/Orange" n'ont pas de sens dans ce cas
  /// (ils ouvriraient l'app sur CE téléphone, pas celui du payeur) : on les
  /// masque et on affiche uniquement le QR, en plus grand.
  final bool displayOnly;

  /// Vérifie qu'un événement reçu sur [confirmationStream] confirme bien
  /// CE paiement précis, pas un autre mouvement de wallet sans rapport
  /// (ex: un retrait qui aboutit pendant qu'une recharge est encore en
  /// attente). `event` = payload du socket, `payment` = réponse de
  /// [initPayment]. Si null, tout événement du flux confirme (les flux déjà
  /// filtrés en amont par orderId, comme le paiement de commande, n'en ont
  /// pas besoin).
  final bool Function(Map<String, dynamic> event, Map<String, dynamic> payment)? matchesConfirmation;

  const SamirpayPaymentSheet({
    super.key,
    required this.amount,
    required this.title,
    required this.initPayment,
    required this.confirmationStream,
    required this.onSuccess,
    this.displayOnly = false,
    this.matchesConfirmation,
  });

  static Future<void> show(
    BuildContext context, {
    required int amount,
    required String title,
    required Future<Map<String, dynamic>> Function() initPayment,
    required Stream<Map<String, dynamic>> confirmationStream,
    required VoidCallback onSuccess,
    bool displayOnly = false,
    bool Function(Map<String, dynamic> event, Map<String, dynamic> payment)? matchesConfirmation,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SamirpayPaymentSheet(
        amount: amount,
        title: title,
        initPayment: initPayment,
        confirmationStream: confirmationStream,
        onSuccess: onSuccess,
        displayOnly: displayOnly,
        matchesConfirmation: matchesConfirmation,
      ),
    );
  }

  @override
  State<SamirpayPaymentSheet> createState() => _SamirpayPaymentSheetState();
}

class _SamirpayPaymentSheetState extends State<SamirpayPaymentSheet> {
  bool _loading = true;
  bool _confirmed = false;
  String? _error;
  Map<String, dynamic>? _payment;
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  void initState() {
    super.initState();
    _init();
    _sub = widget.confirmationStream.listen((event) {
      if (widget.matchesConfirmation != null) {
        if (_payment == null || !widget.matchesConfirmation!(event, _payment!)) return;
      }
      _handleConfirmed();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final result = await widget.initPayment();
      if (!mounted) return;
      setState(() {
        _payment = result;
        _loading = false;
      });
      // Paiement sur le propre téléphone du payeur (pas displayOnly) : on
      // ouvre directement l'app Wave/Orange Money — elle vérifie elle-même
      // le solde du compte, pas besoin de faire scanner un code sur son
      // propre écran.
      if (!widget.displayOnly) {
        final url = result['paymentUrl'] as String?;
        if (url != null) _openUrl(url);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  void _handleConfirmed() {
    if (_confirmed || !mounted) return;
    setState(() => _confirmed = true);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSuccess();
    });
  }

  Future<void> _openUrl(String? url) async {
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      showDemToast(context, "Impossible d'ouvrir l'application.", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return GradientSheet(
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 28),
      child: SingleChildScrollView(child: _buildContent()),
    );
  }

  Widget _buildContent() {
    if (_confirmed) return _buildSuccess();
    if (_loading) return _buildLoading();
    if (_error != null) return _buildError();
    return _buildPayment();
  }

  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Préparation du paiement…', style: TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Handle(),
        const SizedBox(height: 20),
        Icon(Icons.error_outline, color: Colors.red.shade200, size: 40),
        const SizedBox(height: 12),
        Text(_error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        const SizedBox(height: 20),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer', style: TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: 0.20),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.50)),
            ),
            child: const Icon(Icons.check_circle_outline, color: Color(0xFF22C55E), size: 34),
          ),
          const SizedBox(height: 14),
          const Text('Paiement confirmé',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _buildPayment() {
    final payment = _payment!;
    // En mode displayOnly (le livreur montre son écran à quelqu'un d'autre),
    // seul le QR a un sens — personne ne peut ouvrir une app sur SON
    // téléphone à lui pour payer. Sinon (le payeur utilise son propre
    // téléphone), on privilégie l'ouverture directe de l'app, déjà lancée
    // automatiquement dans _init() — pas de QR à faire scanner sur son
    // propre écran.
    final qrCode      = widget.displayOnly ? payment['qrCode'] as String? : null;
    final paymentUrl  = payment['paymentUrl'] as String?;
    // Orange Money renvoie une image QR toute faite ; Wave ne renvoie qu'un
    // lien (voir samirpay.service.js). Wave comme Orange Money ont tous les
    // deux un scanner intégré capable de lire un QR encodant ce type de lien
    // de paiement — on le génère donc nous-mêmes pour Wave, plutôt que de
    // se limiter à Orange Money côté "montrer un QR à quelqu'un d'autre".
    final generatedQrData = (widget.displayOnly && qrCode == null) ? paymentUrl : null;
    final operatorName = payment['operatorName'] as String?;
    final isWave = operatorName == 'WAVE';
    // Préfère le montant confirmé par le serveur (calculé à partir de la
    // commande) à l'estimation locale passée au widget — évite d'afficher un
    // chiffre qui diffère de ce qui sera réellement facturé.
    final amount = (payment['amount'] as num?)?.toInt() ?? widget.amount;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Handle(),
        const SizedBox(height: 16),
        Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('$amount FCFA',
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 20),
        if (qrCode != null) _buildQrCode(qrCode, size: widget.displayOnly ? 240 : 180),
        if (generatedQrData != null) _buildGeneratedQr(generatedQrData, size: 240),
        if (widget.displayOnly) ...[
          const SizedBox(height: 16),
          Text('Faites scanner ce code par Wave ou Orange Money',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.70), fontSize: 13)),
        ],
        const SizedBox(height: 20),
        if (!widget.displayOnly && paymentUrl != null) ...[
          Text('Redirection vers ${isWave ? 'Wave' : 'Orange Money'}…',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.70), fontSize: 13)),
          const SizedBox(height: 14),
          _PaymentAppButton(
            operatorName: operatorName ?? 'ORANGE_MONEY',
            onTap: () => _openUrl(paymentUrl),
          ),
          const SizedBox(height: 20),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
            ),
            SizedBox(width: 10),
            Text('En attente de confirmation…', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer', style: TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }

  Widget _buildQrCode(String qrCode, {required double size}) {
    try {
      final base64Data = qrCode.contains(',') ? qrCode.split(',').last : qrCode;
      final bytes = base64Decode(base64Data);
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Image.memory(bytes, width: size, height: size, fit: BoxFit.contain),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildGeneratedQr(String data, {required double size}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: QrImageView(data: data, size: size, backgroundColor: Colors.white),
    );
  }
}

class _PaymentAppButton extends StatelessWidget {
  final String operatorName;
  final VoidCallback onTap;
  const _PaymentAppButton({required this.operatorName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: PaymentOperatorBadge.colorFor(operatorName),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PaymentOperatorBadge(operatorName: operatorName, size: 26),
            const SizedBox(width: 10),
            Text('Ouvrir ${PaymentOperatorBadge.labelFor(operatorName)}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
