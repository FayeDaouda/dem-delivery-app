import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';
import '../../../core/utils/price_format.dart';

class DemProReceiptScreen extends StatelessWidget {
  final Map<String, dynamic> order;
  const DemProReceiptScreen({super.key, required this.order});

  String _short(String? addr) =>
      (addr == null || addr.isEmpty) ? '—' : addr.split(',').first.trim();

  String _fmtDate(String? iso) {
    final dt = iso != null ? DateTime.tryParse(iso)?.toLocal() : null;
    if (dt == null) return '—';
    const m = ['jan.','fév.','mars','avr.','mai','juin','juil.','août','sep.','oct.','nov.','déc.'];
    final h = dt.hour.toString().padLeft(2, '0');
    final mn = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${m[dt.month - 1]} ${dt.year} à $h:$mn';
  }

  String _duration(String? created, String? delivered) {
    final start = created != null ? DateTime.tryParse(created) : null;
    final end = delivered != null ? DateTime.tryParse(delivered) : null;
    if (start == null || end == null) return '—';
    final diff = end.difference(start);
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    return '${diff.inHours}h${(diff.inMinutes % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final orderId = (order['id'] as String? ?? '').substring(0, 8).toUpperCase();
    final status = order['status'] as String? ?? '';
    final pickup = _short(order['pickupAddress'] as String?);
    final delivery = _short(order['deliveryAddress'] as String?);
    final price = (order['price'] as num?) ?? 0;
    final demFee = (order['demFee'] as num?) ?? 0;
    final total = price + demFee;
    final description = order['description'] as String?;
    final items = (order['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final receiverName = order['receiverName'] as String?;
    final receiverPhone = order['receiverPhone'] as String?;
    final driver = order['driver'] as Map<String, dynamic>?;
    final driverName = driver?['name'] as String?;
    final vehiclePlate = driver?['vehiclePlate'] as String?;
    final createdAt = order['createdAt'] as String?;
    final deliveredAt = order['deliveredAt'] as String?;
    final scheduledAt = order['scheduledAt'] as String?;
    final isDelivered = status == 'DELIVERED';
    final isScheduled = status == 'SCHEDULED';
    final statusAccent = isDelivered
        ? AppColors.successLight
        : isScheduled
        ? AppColors.primary
        : AppColors.error;
    final statusIcon = isDelivered
        ? Icons.check_circle
        : isScheduled
        ? Icons.event_available
        : Icons.cancel;
    final statusTitle = isDelivered
        ? 'Livraison effectuée'
        : isScheduled
        ? 'Livraison programmée'
        : 'Commande annulée';


    return Scaffold(
      backgroundColor: AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: AppColors.lightBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.textDark),
          onPressed: () => context.pop(),
        ),
        title: Text('Reçu #$orderId', style: ClientText.title.copyWith(color: AppColors.textDark)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: AppColors.primary),
            onPressed: () => _shareReceipt(orderId, pickup, delivery, total),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewPadding.bottom + 32),
        child: Column(children: [

          // ── Statut ─────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: statusAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: statusAccent.withValues(alpha: 0.2)),
            ),
            child: Column(children: [
              Icon(statusIcon, color: statusAccent, size: 40),
              const SizedBox(height: 8),
              Text(
                statusTitle,
                style: ClientText.title.copyWith(color: statusAccent),
              ),
              const SizedBox(height: 4),
              Text(
                isScheduled
                    ? 'Prévue le ${_fmtDate(scheduledAt)}'
                    : _fmtDate(deliveredAt ?? createdAt),
                style: ClientText.label.copyWith(color: AppColors.textMuted),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // ── Trajet ─────────────────────────────────────────────────────
          _Card( children: [
            _CardHeader(icon: Icons.route_outlined, label: 'TRAJET'),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.radio_button_on, color: AppColors.successLight, size: 12),
              const SizedBox(width: 10),
              Expanded(child: Text(pickup, style: ClientText.body.copyWith(color: AppColors.textDark))),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 5, top: 2, bottom: 2),
              child: Container(width: 1.5, height: 12, color: AppColors.lightBorder),
            ),
            Row(children: [
              const Icon(Icons.location_on, color: AppColors.error, size: 12),
              const SizedBox(width: 10),
              Expanded(child: Text(delivery, style: ClientText.body.copyWith(color: AppColors.textDark))),
            ]),
            if (receiverName != null || receiverPhone != null) ...[
              const SizedBox(height: 10),
              Divider(color: AppColors.lightBorder, height: 1),
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.person_outline, color: AppColors.textMuted, size: 14),
                const SizedBox(width: 8),
                Text(
                  [if (receiverName != null) receiverName, if (receiverPhone != null) receiverPhone].join(' · '),
                  style: ClientText.label.copyWith(color: AppColors.textMuted),
                ),
              ]),
            ],
          ]),
          const SizedBox(height: 12),

          // ── Colis ──────────────────────────────────────────────────────
          if (description != null && description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Card( children: [
                _CardHeader(icon: Icons.inventory_2_outlined, label: 'COLIS'),
                const SizedBox(height: 8),
                Text(description, style: ClientText.body.copyWith(color: AppColors.textDark)),
              ]),
            ),

          // ── Articles ──────────────────────────────────────────────────
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Card( children: [
                _CardHeader(icon: Icons.shopping_bag_outlined, label: 'ARTICLES'),
                const SizedBox(height: 10),
                ...items.map((item) {
                  final name = item['name'] as String? ?? '—';
                  final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                  final itemPrice = (item['price'] as num?)?.toInt();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Text('•  ', style: ClientText.label.copyWith(color: AppColors.textMuted)),
                      Expanded(child: Text('$name × $qty', style: ClientText.body.copyWith(color: AppColors.textDark))),
                      if (itemPrice != null)
                        Text(formatFcfa(itemPrice * qty), style: ClientText.label.copyWith(color: AppColors.textDark)),
                    ]),
                  );
                }),
                if (items.any((i) => i['price'] != null)) ...[
                  const SizedBox(height: 6),
                  Divider(color: AppColors.lightBorder, height: 1),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text('Total articles', style: ClientText.label.copyWith(color: AppColors.textMuted)),
                    const Spacer(),
                    Text(
                      formatFcfa(items.fold<int>(0, (sum, i) => sum + ((i['price'] as num?)?.toInt() ?? 0) * ((i['quantity'] as num?)?.toInt() ?? 1))),
                      style: ClientText.bodyStrong.copyWith(color: AppColors.successLight),
                    ),
                  ]),
                ],
              ]),
            ),

          // ── Livreur ────────────────────────────────────────────────────
          if (driverName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Card( children: [
                _CardHeader(icon: Icons.two_wheeler, label: 'LIVREUR'),
                const SizedBox(height: 8),
                Row(children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: Text(driverName[0].toUpperCase(), style: ClientText.bodyStrong.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(driverName, style: ClientText.bodyStrong.copyWith(color: AppColors.textDark)),
                    if (vehiclePlate != null)
                      Text(vehiclePlate, style: ClientText.label.copyWith(color: AppColors.textMuted)),
                  ])),
                ]),
              ]),
            ),

          // ── Détail prix ────────────────────────────────────────────────
          _Card( children: [
            _CardHeader(icon: Icons.receipt_long_outlined, label: 'FACTURATION'),
            const SizedBox(height: 12),
            _PriceRow(label: 'Course', value: formatFcfa(price)),
            if (demFee > 0) _PriceRow(label: 'Frais DEM', value: formatFcfa(demFee)),
            const SizedBox(height: 8),
            Divider(color: AppColors.lightBorder, height: 1),
            const SizedBox(height: 8),
            Row(children: [
              Text('Total', style: ClientText.title.copyWith(color: AppColors.textDark, fontSize: 15)),
              const Spacer(),
              Text(formatFcfa(total), style: ClientText.headline.copyWith(color: AppColors.primary, fontSize: 18)),
            ]),
          ]),
          const SizedBox(height: 12),

          // ── Détails ────────────────────────────────────────────────────
          _Card( children: [
            _CardHeader(icon: Icons.info_outline, label: 'DÉTAILS'),
            const SizedBox(height: 8),
            _DetailRow(label: 'N° commande', value: '#$orderId'),
            _DetailRow(label: 'Créée le', value: _fmtDate(createdAt)),
            if (isScheduled && scheduledAt != null)
              _DetailRow(label: 'Programmée pour', value: _fmtDate(scheduledAt)),
            if (deliveredAt != null)
              _DetailRow(label: 'Livrée le', value: _fmtDate(deliveredAt)),
            if (deliveredAt != null)
              _DetailRow(label: 'Durée', value: _duration(createdAt, deliveredAt)),
          ]),
          const SizedBox(height: 24),

          // ── Recommander cette commande ──────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/dem-pro/orders/create', extra: order),
              icon: const Icon(Icons.replay, size: 18),
              label: Text('Recommander cette commande', style: ClientText.subtitle.copyWith(color: AppColors.textDark)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // ── Nouvelle livraison ─────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/dem-pro/orders/create'),
              icon: const Icon(Icons.add, size: 20),
              label: Text('Nouvelle livraison', style: ClientText.subtitle.copyWith(color: AppColors.textDark)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  void _shareReceipt(String orderId, String pickup, String delivery, num total) {
    SharePlus.instance.share(ShareParams(
      text: 'Reçu DEM #$orderId\n$pickup → $delivery\nTotal : ${formatFcfa(total)}\n\nMerci d\'utiliser DEM !',
    ));
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.lightBorder),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

class _CardHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _CardHeader({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: AppColors.primary, size: 16),
    const SizedBox(width: 8),
    Text(label, style: ClientText.label.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w700, letterSpacing: 1)),
  ]);
}

class _PriceRow extends StatelessWidget {
  final String label, value;
  const _PriceRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Text(label, style: ClientText.body.copyWith(color: AppColors.textMuted)),
      const Spacer(),
      Text(value, style: ClientText.bodyStrong.copyWith(color: AppColors.textDark)),
    ]),
  );
}

class _DetailRow extends StatelessWidget {
  final String label, value;
  const _DetailRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Text(label, style: ClientText.label.copyWith(color: AppColors.textMuted)),
      const Spacer(),
      Flexible(child: Text(value, style: ClientText.label.copyWith(color: AppColors.textDark), textAlign: TextAlign.end)),
    ]),
  );
}
