import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/dem_pro_colors.dart';
import '../theme/dem_pro_text.dart';
import '../utils/dem_pro_format.dart';

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
    final isDelivered = status == 'DELIVERED';

    final t = _T(true);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: t.text),
          onPressed: () => context.pop(),
        ),
        title: Text('Reçu #$orderId', style: DemProText.title.copyWith(color: t.text)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: DemProColors.accent),
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
              color: (isDelivered ? DemProColors.success : DemProColors.danger).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: (isDelivered ? DemProColors.success : DemProColors.danger).withValues(alpha: 0.2)),
            ),
            child: Column(children: [
              Icon(
                isDelivered ? Icons.check_circle : Icons.cancel,
                color: isDelivered ? DemProColors.success : DemProColors.danger,
                size: 40,
              ),
              const SizedBox(height: 8),
              Text(
                isDelivered ? 'Livraison effectuée' : 'Commande annulée',
                style: DemProText.title.copyWith(color: isDelivered ? DemProColors.success : DemProColors.danger),
              ),
              const SizedBox(height: 4),
              Text(_fmtDate(deliveredAt ?? createdAt), style: DemProText.caption.copyWith(color: t.muted)),
            ]),
          ),
          const SizedBox(height: 20),

          // ── Trajet ─────────────────────────────────────────────────────
          _Card(t: t, children: [
            _CardHeader(icon: Icons.route_outlined, label: 'TRAJET', t: t),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.radio_button_on, color: DemProColors.success, size: 12),
              const SizedBox(width: 10),
              Expanded(child: Text(pickup, style: DemProText.body.copyWith(color: t.text))),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 5, top: 2, bottom: 2),
              child: Container(width: 1.5, height: 12, color: t.border),
            ),
            Row(children: [
              const Icon(Icons.location_on, color: DemProColors.danger, size: 12),
              const SizedBox(width: 10),
              Expanded(child: Text(delivery, style: DemProText.body.copyWith(color: t.text))),
            ]),
            if (receiverName != null || receiverPhone != null) ...[
              const SizedBox(height: 10),
              Divider(color: t.border, height: 1),
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.person_outline, color: t.muted, size: 14),
                const SizedBox(width: 8),
                Text(
                  [if (receiverName != null) receiverName, if (receiverPhone != null) receiverPhone].join(' · '),
                  style: DemProText.caption.copyWith(color: t.muted),
                ),
              ]),
            ],
          ]),
          const SizedBox(height: 12),

          // ── Colis ──────────────────────────────────────────────────────
          if (description != null && description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Card(t: t, children: [
                _CardHeader(icon: Icons.inventory_2_outlined, label: 'COLIS', t: t),
                const SizedBox(height: 8),
                Text(description, style: DemProText.body.copyWith(color: t.text)),
              ]),
            ),

          // ── Articles ──────────────────────────────────────────────────
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Card(t: t, children: [
                _CardHeader(icon: Icons.shopping_bag_outlined, label: 'ARTICLES', t: t),
                const SizedBox(height: 10),
                ...items.map((item) {
                  final name = item['name'] as String? ?? '—';
                  final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                  final itemPrice = (item['price'] as num?)?.toInt();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Text('•  ', style: DemProText.caption.copyWith(color: t.muted)),
                      Expanded(child: Text('$name × $qty', style: DemProText.body.copyWith(color: t.text))),
                      if (itemPrice != null)
                        Text(DemProFormat.fcfa(itemPrice * qty), style: DemProText.caption.copyWith(color: t.text)),
                    ]),
                  );
                }),
                if (items.any((i) => i['price'] != null)) ...[
                  const SizedBox(height: 6),
                  Divider(color: t.border, height: 1),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text('Total articles', style: DemProText.caption.copyWith(color: t.muted)),
                    const Spacer(),
                    Text(
                      DemProFormat.fcfa(items.fold<int>(0, (sum, i) => sum + ((i['price'] as num?)?.toInt() ?? 0) * ((i['quantity'] as num?)?.toInt() ?? 1))),
                      style: DemProText.bodyStrong.copyWith(color: DemProColors.success),
                    ),
                  ]),
                ],
              ]),
            ),

          // ── Livreur ────────────────────────────────────────────────────
          if (driverName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Card(t: t, children: [
                _CardHeader(icon: Icons.two_wheeler, label: 'LIVREUR', t: t),
                const SizedBox(height: 8),
                Row(children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: DemProColors.accent.withValues(alpha: 0.12),
                    child: Text(driverName[0].toUpperCase(), style: DemProText.bodyStrong.copyWith(color: DemProColors.accent, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(driverName, style: DemProText.bodyStrong.copyWith(color: t.text)),
                    if (vehiclePlate != null)
                      Text(vehiclePlate, style: DemProText.caption.copyWith(color: t.muted)),
                  ])),
                ]),
              ]),
            ),

          // ── Détail prix ────────────────────────────────────────────────
          _Card(t: t, children: [
            _CardHeader(icon: Icons.receipt_long_outlined, label: 'FACTURATION', t: t),
            const SizedBox(height: 12),
            _PriceRow(label: 'Course', value: DemProFormat.fcfa(price), t: t),
            if (demFee > 0) _PriceRow(label: 'Frais DEM', value: DemProFormat.fcfa(demFee), t: t),
            const SizedBox(height: 8),
            Divider(color: t.border, height: 1),
            const SizedBox(height: 8),
            Row(children: [
              Text('Total', style: DemProText.title.copyWith(color: t.text, fontSize: 15)),
              const Spacer(),
              Text(DemProFormat.fcfa(total), style: DemProText.headline.copyWith(color: DemProColors.accent, fontSize: 18)),
            ]),
          ]),
          const SizedBox(height: 12),

          // ── Détails ────────────────────────────────────────────────────
          _Card(t: t, children: [
            _CardHeader(icon: Icons.info_outline, label: 'DÉTAILS', t: t),
            const SizedBox(height: 8),
            _DetailRow(label: 'N° commande', value: '#$orderId', t: t),
            _DetailRow(label: 'Créée le', value: _fmtDate(createdAt), t: t),
            if (deliveredAt != null)
              _DetailRow(label: 'Livrée le', value: _fmtDate(deliveredAt), t: t),
            if (deliveredAt != null)
              _DetailRow(label: 'Durée', value: _duration(createdAt, deliveredAt), t: t),
          ]),
          const SizedBox(height: 24),

          // ── Recommander cette commande ──────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/dem-pro/orders/create', extra: order),
              icon: const Icon(Icons.replay, size: 18),
              label: const Text('Recommander cette commande', style: DemProText.subtitle),
              style: OutlinedButton.styleFrom(
                foregroundColor: DemProColors.accent,
                side: const BorderSide(color: DemProColors.accent),
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
              label: const Text('Nouvelle livraison', style: DemProText.subtitle),
              style: ElevatedButton.styleFrom(
                backgroundColor: DemProColors.accent,
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
      text: 'Reçu DEM #$orderId\n$pickup → $delivery\nTotal : ${DemProFormat.fcfa(total)}\n\nMerci d\'utiliser DEM !',
    ));
  }
}

// ── Theme helper ─────────────────────────────────────────────────────────────

class _T {
  final bool dark;
  const _T(this.dark);
  Color get bg     => dark ? DemProColors.bg    : DemProColors.lightBg;
  Color get cardBg => dark ? DemProColors.bg2   : Colors.white;
  Color get border => dark ? DemProColors.bg3   : DemProColors.lightBorder;
  Color get text   => dark ? DemProColors.text  : DemProColors.lightText;
  Color get muted  => dark ? DemProColors.muted : DemProColors.lightMuted;
}

// ── Widgets ──────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final _T t;
  final List<Widget> children;
  const _Card({required this.t, required this.children});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: t.cardBg,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: t.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

class _CardHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final _T t;
  const _CardHeader({required this.icon, required this.label, required this.t});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: DemProColors.accent, size: 16),
    const SizedBox(width: 8),
    Text(label, style: DemProText.caption.copyWith(color: t.muted, fontWeight: FontWeight.w700, letterSpacing: 1)),
  ]);
}

class _PriceRow extends StatelessWidget {
  final String label, value;
  final _T t;
  const _PriceRow({required this.label, required this.value, required this.t});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Text(label, style: DemProText.body.copyWith(color: t.muted)),
      const Spacer(),
      Text(value, style: DemProText.bodyStrong.copyWith(color: t.text)),
    ]),
  );
}

class _DetailRow extends StatelessWidget {
  final String label, value;
  final _T t;
  const _DetailRow({required this.label, required this.value, required this.t});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Text(label, style: DemProText.caption.copyWith(color: t.muted)),
      const Spacer(),
      Flexible(child: Text(value, style: DemProText.caption.copyWith(color: t.text), textAlign: TextAlign.end)),
    ]),
  );
}
