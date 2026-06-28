import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/dem_pro_colors.dart';

class DemProReceiptScreen extends StatelessWidget {
  final Map<String, dynamic> order;
  const DemProReceiptScreen({super.key, required this.order});

  String _short(String? addr) =>
      (addr == null || addr.isEmpty) ? '—' : addr.split(',').first.trim();

  String _fcfa(num value) {
    final s = value.round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '$buf FCFA';
  }

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
        title: Text('Reçu #$orderId', style: TextStyle(color: t.text, fontSize: 16, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: DemProColors.accent),
            onPressed: () => _shareReceipt(orderId, pickup, delivery, total),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
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
                style: TextStyle(
                  color: isDelivered ? DemProColors.success : DemProColors.danger,
                  fontSize: 16, fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(_fmtDate(deliveredAt ?? createdAt), style: TextStyle(color: t.muted, fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 20),

          // ── Trajet ─────────────────────────────────────────────────────
          _Card(t: t, children: [
            _CardHeader(icon: Icons.route, label: 'TRAJET', t: t),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.radio_button_on, color: DemProColors.success, size: 12),
              const SizedBox(width: 10),
              Expanded(child: Text(pickup, style: TextStyle(color: t.text, fontSize: 13))),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 5, top: 2, bottom: 2),
              child: Container(width: 1.5, height: 12, color: t.border),
            ),
            Row(children: [
              const Icon(Icons.location_on, color: DemProColors.danger, size: 12),
              const SizedBox(width: 10),
              Expanded(child: Text(delivery, style: TextStyle(color: t.text, fontSize: 13))),
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
                  style: TextStyle(color: t.muted, fontSize: 12),
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
                Text(description, style: TextStyle(color: t.text, fontSize: 13)),
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
                      Text('•  ', style: TextStyle(color: t.muted, fontSize: 12)),
                      Expanded(child: Text('$name × $qty', style: TextStyle(color: t.text, fontSize: 13))),
                      if (itemPrice != null)
                        Text(_fcfa(itemPrice * qty), style: TextStyle(color: t.text, fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                  );
                }),
                if (items.any((i) => i['price'] != null)) ...[
                  const SizedBox(height: 6),
                  Divider(color: t.border, height: 1),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text('Total articles', style: TextStyle(color: t.muted, fontSize: 12)),
                    const Spacer(),
                    Text(
                      _fcfa(items.fold<int>(0, (sum, i) => sum + ((i['price'] as num?)?.toInt() ?? 0) * ((i['quantity'] as num?)?.toInt() ?? 1))),
                      style: const TextStyle(color: DemProColors.success, fontSize: 13, fontWeight: FontWeight.w700),
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
                    child: Text(driverName[0].toUpperCase(), style: const TextStyle(color: DemProColors.accent, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(driverName, style: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w600)),
                    if (vehiclePlate != null)
                      Text(vehiclePlate, style: TextStyle(color: t.muted, fontSize: 11)),
                  ])),
                ]),
              ]),
            ),

          // ── Détail prix ────────────────────────────────────────────────
          _Card(t: t, children: [
            _CardHeader(icon: Icons.receipt_long, label: 'FACTURATION', t: t),
            const SizedBox(height: 12),
            _PriceRow(label: 'Course', value: _fcfa(price), t: t),
            if (demFee > 0) _PriceRow(label: 'Frais DEM', value: _fcfa(demFee), t: t),
            const SizedBox(height: 8),
            Divider(color: t.border, height: 1),
            const SizedBox(height: 8),
            Row(children: [
              Text('Total', style: TextStyle(color: t.text, fontSize: 15, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(_fcfa(total), style: const TextStyle(color: DemProColors.accent, fontSize: 18, fontWeight: FontWeight.w900)),
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

          // ── Nouvelle livraison ─────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/dem-pro/orders/create'),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Nouvelle livraison', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
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
      text: 'Reçu DEM #$orderId\n$pickup → $delivery\nTotal : ${_fcfa(total)}\n\nMerci d\'utiliser DEM !',
    ));
  }
}

// ── Theme helper ─────────────────────────────────────────────────────────────

class _T {
  final bool dark;
  const _T(this.dark);
  Color get bg     => dark ? DemProColors.bg    : const Color(0xFFF8FAFC);
  Color get cardBg => dark ? DemProColors.bg2   : Colors.white;
  Color get border => dark ? DemProColors.bg3   : const Color(0xFFE2E8F0);
  Color get text   => dark ? DemProColors.text  : const Color(0xFF0F172A);
  Color get muted  => dark ? DemProColors.muted : const Color(0xFF64748B);
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
    Text(label, style: TextStyle(color: t.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
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
      Text(label, style: TextStyle(color: t.muted, fontSize: 13)),
      const Spacer(),
      Text(value, style: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w600)),
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
      Text(label, style: TextStyle(color: t.muted, fontSize: 12)),
      const Spacer(),
      Flexible(child: Text(value, style: TextStyle(color: t.text, fontSize: 12, fontWeight: FontWeight.w600), textAlign: TextAlign.end)),
    ]),
  );
}
