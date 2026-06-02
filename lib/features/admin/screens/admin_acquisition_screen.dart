import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dem_layout.dart';
import '../admin_session.dart';

class AdminAcquisitionScreen extends StatefulWidget {
  const AdminAcquisitionScreen({super.key});
  @override
  State<AdminAcquisitionScreen> createState() => _AdminAcquisitionScreenState();
}

class _AdminAcquisitionScreenState extends State<AdminAcquisitionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // ── Forfait ──
  Map<String, dynamic>? _forfait;
  bool _forfaitLoading = true;
  bool _processingForfait = false;
  final _amountCtrl = TextEditingController();

  // ── Free course ──
  Map<String, dynamic>? _freeCourse;
  bool _freeCourseLoading = true;

  // ── Referrals ──
  Map<String, dynamic>? _referrals;
  bool _referralsLoading = true;

  // ── Fees ──
  Map<String, dynamic>? _fees;
  bool _feesLoading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() { if (!_tabs.indexIsChanging) setState(() {}); });
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    _loadForfait();
    _loadFreeCourse();
    _loadReferrals();
    _loadFees();
  }

  Future<void> _loadForfait() async {
    setState(() => _forfaitLoading = true);
    try {
      final r = await AdminSession.dio.get('/admin/forfait/summary');
      final cfg = await AdminSession.dio.get('/admin/config');
      final configList = cfg.data as List;
      final map = { for (var e in configList) (e['key'] as String): e['value'] as String };
      if (mounted) setState(() {
        _forfait = {
          ...r.data,
          'active':    map['forfait_active'] == 'true',
          'amount':    int.tryParse(map['forfait_amount'] ?? '480') ?? 480,
          'amountM3':  int.tryParse(map['forfait_amount_m3'] ?? '650') ?? 650,
        };
        _amountCtrl.text = _forfait!['amount'].toString();
        _forfaitLoading = false;
      });
    } catch (_) { if (mounted) setState(() => _forfaitLoading = false); }
  }

  Future<void> _loadFreeCourse() async {
    setState(() => _freeCourseLoading = true);
    try {
      final r = await AdminSession.dio.get('/admin/acquisition/free-course');
      if (mounted) setState(() { _freeCourse = r.data; _freeCourseLoading = false; });
    } catch (_) { if (mounted) setState(() => _freeCourseLoading = false); }
  }

  Future<void> _loadReferrals() async {
    setState(() => _referralsLoading = true);
    try {
      final r = await AdminSession.dio.get('/admin/acquisition/referrals');
      if (mounted) setState(() { _referrals = r.data; _referralsLoading = false; });
    } catch (_) { if (mounted) setState(() => _referralsLoading = false); }
  }

  Future<void> _loadFees() async {
    setState(() => _feesLoading = true);
    try {
      final r = await AdminSession.dio.get('/admin/acquisition/fees');
      if (mounted) setState(() { _fees = r.data; _feesLoading = false; });
    } catch (_) { if (mounted) setState(() => _feesLoading = false); }
  }

  // ── Actions Forfait ────────────────────────────────────────────────────────

  Future<void> _toggleForfait(bool active) async {
    try {
      await AdminSession.dio.put('/admin/forfait/config', data: {'active': active});
      await _loadForfait();
      _snack(active ? 'Forfait activé ✓' : 'Forfait désactivé', success: active);
    } catch (e) { _snack('Erreur : $e', success: false); }
  }

  Future<void> _saveForfaitAmount() async {
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount < 0) return;
    try {
      await AdminSession.dio.put('/admin/forfait/config', data: {'amount': amount});
      await _loadForfait();
      _snack('Montant mis à jour : $amount FCFA/jour ✓');
    } catch (e) { _snack('Erreur : $e', success: false); }
  }

  Future<void> _processForfait() async {
    final confirm = await _confirm(
      'Déclencher le prélèvement ?',
      'Cela va créer les enregistrements de forfait pour tous les drivers actifs aujourd\'hui.',
    );
    if (confirm != true) return;
    setState(() => _processingForfait = true);
    try {
      final r = await AdminSession.dio.post('/admin/forfait/process');
      final charged = r.data['charged'] as int? ?? 0;
      _snack('$charged driver(s) prélevé(s) aujourd\'hui ✓');
      await _loadForfait();
    } catch (e) { _snack('Erreur : $e', success: false); }
    if (mounted) setState(() => _processingForfait = false);
  }

  Future<bool?> _confirm(String title, String msg) => showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
      content: Text(msg, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler', style: TextStyle(color: AppColors.textSecondary))),
        TextButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmer', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold))),
      ],
    ),
  );

  void _snack(String msg, {bool success = true}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? AppColors.primary : AppColors.error,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: DemLayout.formMaxWidth(context)),
      child: Column(
      children: [
        // TabBar
        Container(
          color: AppColors.surface,
          child: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            tabs: const [
              Tab(text: 'FORFAIT'),
              Tab(text: '100 CLIENTS'),
              Tab(text: 'PARRAINAGE'),
              Tab(text: 'FRAIS'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildForfaitTab(),
              _buildFreeCourseTab(),
              _buildReferralsTab(),
              _buildFeesTab(),
            ],
          ),
        ),
      ],
      ),    // Column
    );    // ConstrainedBox
  }

  // ── Tab Forfait ────────────────────────────────────────────────────────────
  Widget _buildForfaitTab() {
    if (_forfaitLoading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    final f = _forfait ?? {};
    final active     = f['active'] as bool? ?? false;
    final amount     = f['amount'] as int? ?? 480;
    final totalOwed  = (f['totalOwed'] as num?)?.toInt() ?? 0;
    final records    = f['recordCount'] as int? ?? 0;
    final drivers    = f['driverCount'] as int? ?? 0;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadForfait,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Statut ON/OFF
          _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _Label('Activation forfait'),
              const Spacer(),
              Switch(
                value: active,
                activeThumbColor: AppColors.primary,
                onChanged: _toggleForfait,
              ),
            ]),
            Text(
              active
                  ? 'Actif — $amount FCFA/jour prélevés'
                  : 'Inactif — aucun prélèvement',
              style: TextStyle(
                color: active ? AppColors.primary : AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text('⚠ Toute modification s\'applique au prochain prélèvement (jour suivant)',
                style: TextStyle(color: Colors.orange.withValues(alpha: 0.85), fontSize: 11)),
          ])),
          const SizedBox(height: 12),

          // Modifier le montant
          _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Label('Montant journalier (FCFA)'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _amountCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    hintText: '$amount',
                    hintStyle: const TextStyle(color: AppColors.textSecondary),
                    fillColor: AppColors.background,
                    filled: true,
                    suffixText: 'FCFA/jour',
                    suffixStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _saveForfaitAmount,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('Sauver',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              _QuickBtn('480 FCFA (S4)', () { _amountCtrl.text = '480'; _saveForfaitAmount(); }),
              _QuickBtn('650 FCFA (M3)', () { _amountCtrl.text = '650'; _saveForfaitAmount(); }),
              _QuickBtn('Promo 0', () { _amountCtrl.text = '0'; _saveForfaitAmount(); }),
            ]),
          ])),
          const SizedBox(height: 12),

          // Résumé
          Row(children: [
            Expanded(child: _StatBox(label: 'Total dû', value: '$totalOwed FCFA',
                color: totalOwed > 0 ? AppColors.error : AppColors.success)),
            const SizedBox(width: 10),
            Expanded(child: _StatBox(label: 'Enregistrements', value: '$records')),
            const SizedBox(width: 10),
            Expanded(child: _StatBox(label: 'Drivers concernés', value: '$drivers')),
          ]),
          const SizedBox(height: 12),

          // Bouton déclencher
          GestureDetector(
            onTap: _processingForfait ? null : _processForfait,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: active ? AppColors.primary.withValues(alpha: 0.4) : AppColors.textSecondary.withValues(alpha: 0.2),
                ),
              ),
              child: Center(
                child: _processingForfait
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.play_arrow_rounded,
                            color: active ? AppColors.primary : AppColors.textSecondary, size: 18),
                        const SizedBox(width: 6),
                        Text('Déclencher le prélèvement du jour',
                            style: TextStyle(
                              color: active ? AppColors.primary : AppColors.textSecondary,
                              fontSize: 13, fontWeight: FontWeight.w600,
                            )),
                      ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 100 Clients ────────────────────────────────────────────────────────
  Widget _buildFreeCourseTab() {
    if (_freeCourseLoading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    final d = _freeCourse ?? {};
    final slots     = d['slots'] as int? ?? 100;
    final filled    = d['filled'] as int? ?? 0;
    final remaining = d['remaining'] as int? ?? 100;
    final used      = d['usedCount'] as int? ?? 0;
    final clients   = (d['clients'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadFreeCourse,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Compteur
          _Card(child: Column(children: [
            Row(children: [
              Expanded(child: _StatBox(label: 'Places occupées', value: '$filled / $slots')),
              const SizedBox(width: 8),
              Expanded(child: _StatBox(label: 'Restantes', value: '$remaining',
                  color: remaining > 10 ? AppColors.success : AppColors.error)),
              const SizedBox(width: 8),
              Expanded(child: _StatBox(label: 'Offre utilisée', value: '$used', color: AppColors.primary)),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: filled / slots,
                minHeight: 8,
                backgroundColor: AppColors.background,
                valueColor: AlwaysStoppedAnimation<Color>(
                  filled >= slots ? AppColors.error : AppColors.primary,
                ),
              ),
            ),
          ])),
          const SizedBox(height: 12),

          // Liste clients
          ...clients.map((c) {
            final usedOffer = c['usedOffer'] as bool? ?? false;
            return _Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Center(child: Text('${c['rank']}',
                      style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold))),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c['name'] as String? ?? '—',
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(c['phone'] as String? ?? '',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${c['totalOrders']} commande(s)',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: usedOffer
                          ? AppColors.success.withValues(alpha: 0.12)
                          : AppColors.card,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      usedOffer ? '🎁 Utilisée' : 'Non utilisée',
                      style: TextStyle(
                        color: usedOffer ? AppColors.success : AppColors.textSecondary,
                        fontSize: 10, fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ]),
              ]),
            );
          }),
        ],
      ),
    );
  }

  // ── Tab Parrainage ─────────────────────────────────────────────────────────
  Widget _buildReferralsTab() {
    if (_referralsLoading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    final d = _referrals ?? {};
    final total   = d['totalReferrals'] as int? ?? 0;
    final credits = (d['totalCreditsDistributed'] as num?)?.toInt() ?? 0;
    final referrers = (d['referrers'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadReferrals,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(child: _StatBox(label: 'Total parrainages', value: '$total')),
            const SizedBox(width: 10),
            Expanded(child: _StatBox(label: 'Crédits distribués', value: '$credits FCFA', color: AppColors.primary)),
          ]),
          const SizedBox(height: 12),

          if (referrers.isEmpty)
            const Center(child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('Aucun parrainage pour l\'instant',
                  style: TextStyle(color: AppColors.textSecondary)),
            ))
          else
            ...referrers.map((r) {
              final count = r['referralCount'] as int? ?? 0;
              final referred = (r['referrals'] as List?)?.cast<Map<String, dynamic>>() ?? [];
              return _Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                      child: const Icon(Icons.person, color: AppColors.primary, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r['name'] as String? ?? '—',
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
                      Text(r['phone'] as String? ?? '',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    ])),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('$count filleul${count != 1 ? 's' : ''}',
                          style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                  if (referred.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Divider(color: Color(0x0FFFFFFF), height: 1),
                    const SizedBox(height: 6),
                    ...referred.take(3).map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 3, left: 46),
                      child: Text('↳ ${f['name'] ?? f['phone'] ?? '—'}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    )),
                    if (referred.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(left: 46, top: 2),
                        child: Text('+ ${referred.length - 3} autre(s)',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                      ),
                  ],
                ]),
              );
            }),
        ],
      ),
    );
  }

  // ── Tab Frais ──────────────────────────────────────────────────────────────
  Widget _buildFeesTab() {
    if (_feesLoading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    final d = _fees ?? {};
    final grid  = (d['grid'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final total = (d['totalFeesCollected'] as num?)?.toInt() ?? 0;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _loadFees,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatBox(label: 'Total frais collectés', value: '$total FCFA', color: AppColors.primary),
          const SizedBox(height: 12),
          _Card(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Label('Grille tarifaire'),
              const SizedBox(height: 4),
              const Text('Appliquée automatiquement côté serveur à chaque commande.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              const SizedBox(height: 12),
              // En-tête
              Row(children: const [
                Expanded(flex: 3, child: Text('Tranche (FCFA)', style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w700))),
                Expanded(flex: 2, child: Text('Frais', style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w700))),
                Expanded(flex: 2, child: Text('Volume', textAlign: TextAlign.right, style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w700))),
              ]),
              const Divider(color: Color(0x0FFFFFFF), height: 16),
              ...grid.map((tier) {
                final min  = (tier['min'] as num).toInt();
                final max  = (tier['max'] as num).toInt();
                final fee  = (tier['fee'] as num).toInt();
                final pct  = (tier['pct'] as num?)?.toInt() ?? 0;
                final count = (tier['count'] as num?)?.toInt() ?? 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Expanded(flex: 3, child: Text('$min — $max',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12))),
                    Expanded(flex: 2, child: Text('$fee FCFA',
                        style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700))),
                    Expanded(flex: 2, child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Text('$count ($pct%)',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    ])),
                  ]),
                );
              }),
            ],
          )),
        ],
      ),
    );
  }
}

// ── Widgets helpers ───────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets margin;
  const _Card({required this.child, this.margin = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) => Container(
    margin: margin,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
    ),
    child: child,
  );
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _StatBox({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
    decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(color: color ?? AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
    ]),
  );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: 0.5));
}

class _QuickBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickBtn(this.label, this.onTap);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Text(label, style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
    ),
  );
}
