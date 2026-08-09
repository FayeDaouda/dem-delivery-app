import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';
import '../../../core/utils/price_format.dart';
import '../data/dem_pro_repository.dart';

String _initials(String? name) {
  if (name == null || name.trim().isEmpty) return '?';
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.length >= 2
      ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
      : parts[0][0].toUpperCase();
}

String _fmtDate(String? iso) {
  final dt = iso != null ? DateTime.tryParse(iso)?.toLocal() : null;
  if (dt == null) return '—';
  const m = [
    'jan.', 'fév.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sep.', 'oct.', 'nov.', 'déc.',
  ];
  return '${dt.day} ${m[dt.month - 1]} ${dt.year}';
}

class DemProClientsScreen extends StatefulWidget {
  const DemProClientsScreen({super.key});
  @override
  State<DemProClientsScreen> createState() => _DemProClientsScreenState();
}

class _DemProClientsScreenState extends State<DemProClientsScreen> {
  final _repo = DemProRepository(ApiClient.dio);
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _clients = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final clients = await _repo.getClients();
      if (!mounted) return;
      setState(() {
        _clients = clients;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de charger vos clients.';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.isEmpty) return _clients;
    final q = _query.toLowerCase();
    return _clients.where((c) {
      final name = (c['name'] as String? ?? '').toLowerCase();
      final phone = (c['phone'] as String? ?? '').toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => FocusScope.of(context).unfocus(),
    behavior: HitTestBehavior.translucent,
    child: Scaffold(
      backgroundColor: AppColors.lightBg,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => context.pop(),
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'Mes clients',
                            style: ClientText.title.copyWith(color: Colors.white, fontSize: 18),
                          ),
                        ),
                        if (!_loading && _clients.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_clients.length}',
                              style: ClientText.micro.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() => _query = v.trim()),
                          cursorColor: AppColors.primary,
                          style: ClientText.body.copyWith(color: AppColors.textDark),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: false,
                            hintText: 'Rechercher un client…',
                            hintStyle: ClientText.body.copyWith(color: AppColors.textMuted),
                            prefixIcon: const Icon(Icons.search, color: AppColors.primary, size: 20),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 36),
                        const SizedBox(height: 12),
                        Text(_error!, style: ClientText.body.copyWith(color: AppColors.textMuted)),
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: _load,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('Réessayer', style: ClientText.button.copyWith(fontSize: 14)),
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: _load,
                    child: _filtered.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: MediaQuery.of(context).size.height * 0.5,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        _clients.isEmpty ? Icons.people_outline : Icons.search_off_rounded,
                                        color: AppColors.textMuted,
                                        size: 40,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        _clients.isEmpty
                                            ? 'Aucun client pour le moment'
                                            : 'Aucun résultat',
                                        style: ClientText.subtitle.copyWith(color: AppColors.textDark, fontSize: 15),
                                      ),
                                      const SizedBox(height: 6),
                                      if (_clients.isEmpty)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 40),
                                          child: Text(
                                            'Vos clients apparaîtront ici après leurs premières livraisons.',
                                            style: ClientText.body.copyWith(color: AppColors.textMuted, height: 1.4),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, i) => _ClientRow(
                              client: _filtered[i],
                              onTap: () => context.push('/dem-pro/clients/detail', extra: _filtered[i]),
                            ),
                          ),
                  ),
          ),
        ],
      ),
    ),
  );
}

class _ClientRow extends StatelessWidget {
  final Map<String, dynamic> client;
  final VoidCallback onTap;
  const _ClientRow({required this.client, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = client['name'] as String?;
    final phone = client['phone'] as String? ?? '';
    final orderCount = (client['orderCount'] as num?)?.toInt() ?? 0;
    final totalSpent = (client['totalSpent'] as num?) ?? 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.lightBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  _initials(name),
                  style: ClientText.bodyStrong.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name?.isNotEmpty == true ? name! : phone,
                    style: ClientText.bodyStrong.copyWith(color: AppColors.textDark),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$orderCount commande${orderCount > 1 ? 's' : ''}',
                    style: ClientText.label.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatFcfa(totalSpent),
                  style: ClientText.bodyStrong.copyWith(color: AppColors.successLight),
                ),
                const SizedBox(height: 2),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Détail client
// ─────────────────────────────────────────────────────────────────────────────

class DemProClientDetailScreen extends StatefulWidget {
  final Map<String, dynamic> client;
  const DemProClientDetailScreen({super.key, required this.client});
  @override
  State<DemProClientDetailScreen> createState() => _DemProClientDetailScreenState();
}

class _DemProClientDetailScreenState extends State<DemProClientDetailScreen> {
  final _repo = DemProRepository(ApiClient.dio);
  bool _loading = true;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final phone = widget.client['phone'] as String?;
      final all = await _repo.getMyOrders(limit: 100);
      if (!mounted) return;
      setState(() {
        _orders = all
            .where((o) => o['receiverPhone'] == phone && o['status'] == 'DELIVERED')
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _call(String phone) => launchUrl(Uri.parse('tel:$phone'));

  void _whatsapp(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    launchUrl(
      Uri.parse('https://wa.me/$digits'),
      mode: LaunchMode.externalApplication,
    );
  }

  void _newOrderForClient() {
    // Réutilise la commande la plus récente comme gabarit (adresse +
    // coordonnées déjà géocodées) — plus fiable qu'une adresse texte seule,
    // voir _applyReorder dans dem_pro_order_create_screen.dart.
    final template = _orders.isNotEmpty
        ? _orders.first
        : {
            'receiverName': widget.client['name'],
            'receiverPhone': widget.client['phone'],
            'deliveryAddress': widget.client['lastAddress'],
          };
    context.push('/dem-pro/orders/create', extra: template);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.client['name'] as String?;
    final phone = widget.client['phone'] as String? ?? '';
    final orderCount = (widget.client['orderCount'] as num?)?.toInt() ?? 0;
    final totalSpent = (widget.client['totalSpent'] as num?) ?? 0;
    final lastOrderAt = widget.client['lastOrderAt'] as String?;
    final lastAddress = widget.client['lastAddress'] as String?;

    return Scaffold(
      backgroundColor: AppColors.lightBg,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => context.pop(),
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.20),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                _initials(name),
                                style: ClientText.title.copyWith(color: Colors.white, fontSize: 18),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name?.isNotEmpty == true ? name! : phone,
                                  style: ClientText.title.copyWith(color: Colors.white, fontSize: 18),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  phone,
                                  style: ClientText.micro.copyWith(color: Colors.white.withValues(alpha: 0.75)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: _StatChip(label: 'Commandes', value: '$orderCount'),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StatChip(label: 'Total dépensé', value: formatFcfa(totalSpent)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.call_outlined,
                        label: 'Appeler',
                        onTap: () => _call(phone),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.chat_bubble_outline,
                        label: 'WhatsApp',
                        onTap: () => _whatsapp(phone),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _newOrderForClient,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Nouvelle livraison pour ce client'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (lastAddress != null && lastAddress.isNotEmpty) ...[
                  Text(
                    'Dernière adresse',
                    style: ClientText.label.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    lastAddress,
                    style: ClientText.body.copyWith(color: AppColors.textDark),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Dernière commande : ${_fmtDate(lastOrderAt)}',
                    style: ClientText.micro.copyWith(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 20),
                ],
                Text(
                  'Historique',
                  style: ClientText.bodyStrong.copyWith(color: AppColors.textDark),
                ),
                const SizedBox(height: 10),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                  )
                else if (_orders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Aucune commande livrée trouvée dans les 100 dernières.',
                      style: ClientText.body.copyWith(color: AppColors.textMuted),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.lightBorder),
                    ),
                    child: Column(
                      children: [
                        for (int i = 0; i < _orders.length; i++)
                          _HistoryRow(order: _orders[i], isLast: i == _orders.length - 1),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: ClientText.subtitle.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        Text(
          label,
          style: ClientText.micro.copyWith(color: Colors.white.withValues(alpha: 0.75)),
        ),
      ],
    ),
  );
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: ClientText.bodyStrong.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    ),
  );
}

class _HistoryRow extends StatelessWidget {
  final Map<String, dynamic> order;
  final bool isLast;
  const _HistoryRow({required this.order, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final address = (order['deliveryAddress'] as String? ?? '').split(',').first.trim();
    final price = (order['price'] as num?) ?? 0;
    final items = (order['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    int productTotal = 0;
    for (final it in items) {
      productTotal += ((it['price'] as num?)?.toInt() ?? 0) * ((it['quantity'] as num?)?.toInt() ?? 1);
    }
    final total = price + productTotal;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: AppColors.lightBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  address.isEmpty ? '—' : address,
                  style: ClientText.bodyStrong.copyWith(color: AppColors.textDark),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _fmtDate(order['deliveredAt'] as String? ?? order['createdAt'] as String?),
                  style: ClientText.label.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Text(
            formatFcfa(total),
            style: ClientText.bodyStrong.copyWith(color: AppColors.textDark),
          ),
        ],
      ),
    );
  }
}
