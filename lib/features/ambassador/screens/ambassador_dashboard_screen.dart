import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../data/ambassador_repository.dart';

const _purple = Color(0xFF7C3AED);
const _purple2 = Color(0xFF5B21B6);

class AmbassadorDashboardScreen extends StatefulWidget {
  const AmbassadorDashboardScreen({super.key});
  @override
  State<AmbassadorDashboardScreen> createState() => _State();
}

class _State extends State<AmbassadorDashboardScreen> with SingleTickerProviderStateMixin {
  final _repo     = AmbassadorRepository(ApiClient.dio);
  late TabController _tabs;

  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _drivers = [];
  bool _loadingStats   = true;
  bool _loadingDrivers = true;
  String _driverFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadStats();
    _loadDrivers();
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _loadStats() async {
    try {
      final s = await _repo.getStats();
      if (mounted) setState(() { _stats = s; _loadingStats = false; });
    } catch (_) { if (mounted) setState(() => _loadingStats = false); }
  }

  Future<void> _loadDrivers() async {
    setState(() => _loadingDrivers = true);
    try {
      final filter = _driverFilter == 'all' ? null : _driverFilter;
      final list = await _repo.getDrivers(status: filter);
      if (mounted) setState(() { _drivers = list; _loadingDrivers = false; });
    } catch (_) { if (mounted) setState(() => _loadingDrivers = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F3FF),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: _purple,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [_purple, _purple2], begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text('Mon espace Ambassadeur', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 4),
                    const Text('DEM Ambassador', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Ajouter un livreur',
                onPressed: () => Navigator.of(context).pushNamed('/ambassador/add-driver').then((_) => _loadDrivers()),
              ),
            ],
          ),

          // Stats cards
          SliverToBoxAdapter(
            child: _loadingStats
                ? const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: _purple)))
                : _buildStats(),
          ),

          // Drivers section header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                const Text('Mes livreurs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.refresh, size: 18), onPressed: _loadDrivers),
              ]),
            ),
          ),

          // Filter chips
          SliverToBoxAdapter(
            child: SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final f in [
                    ('all',       'Tous'),
                    ('active',    'Actifs'),
                    ('pending',   'En attente'),
                    ('rejected',  'Refusés'),
                    ('suspended', 'Suspendus'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(f.$2, style: TextStyle(fontSize: 12, color: _driverFilter == f.$1 ? Colors.white : _purple)),
                        selected: _driverFilter == f.$1,
                        onSelected: (_) { setState(() => _driverFilter = f.$1); _loadDrivers(); },
                        selectedColor: _purple,
                        backgroundColor: _purple.withValues(alpha: 0.08),
                        showCheckmark: false,
                        side: BorderSide(color: _purple.withValues(alpha: 0.25)),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Driver list
          _loadingDrivers
              ? const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: _purple))))
              : _drivers.isEmpty
                  ? SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(children: [
                          const Icon(Icons.group_outlined, color: Colors.grey, size: 48),
                          const SizedBox(height: 12),
                          const Text('Aucun livreur', style: TextStyle(color: Colors.grey)),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Ajouter un livreur'),
                            onPressed: () => Navigator.of(context).pushNamed('/ambassador/add-driver').then((_) => _loadDrivers()),
                            style: ElevatedButton.styleFrom(backgroundColor: _purple, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                          ),
                        ]),
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _DriverTile(driver: _drivers[i]),
                          childCount: _drivers.length,
                        ),
                      ),
                    ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).pushNamed('/ambassador/add-driver').then((_) => _loadDrivers()),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter livreur'),
        backgroundColor: _purple,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildStats() {
    final s = _stats!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          Row(children: [
            _StatCard(label: 'Flotte active',   value: '${s['activeCount'] ?? 0}', icon: Icons.check_circle_outline, color: Colors.green),
            const SizedBox(width: 10),
            _StatCard(label: 'En attente',      value: '${s['pendingCount'] ?? 0}', icon: Icons.hourglass_top_rounded, color: Colors.orange),
            const SizedBox(width: 10),
            _StatCard(label: 'Courses total',   value: '${s['totalCourses'] ?? 0}', icon: Icons.motorcycle, color: _purple),
          ]),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)]),
            child: Row(children: [
              const Icon(Icons.directions_bike, color: _purple, size: 20),
              const SizedBox(width: 10),
              Text('Flotte : ${s['fleetSize'] ?? 0} / ${s['fleetMax'] ?? 10} motos', style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              if ((s['fleetSize'] ?? 0) >= (s['fleetMax'] ?? 10))
                GestureDetector(
                  onTap: _showFleetExtensionDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: _purple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Text('+ Extension', style: TextStyle(color: _purple, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ),
            ]),
          ),
          if (!((s['isFleetReady'] as bool?) ?? true))
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.shade200)),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                const Expanded(child: Text('Minimum 3 livreurs actifs requis pour être opérationnel.', style: TextStyle(fontSize: 12, color: Colors.orange))),
              ]),
            ),
        ],
      ),
    );
  }

  void _showFleetExtensionDialog() {
    final sizeCtrl = TextEditingController();
    final justCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Demander une extension'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: sizeCtrl, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Nombre de motos demandé', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: justCtrl, maxLines: 3,
            decoration: const InputDecoration(labelText: 'Justification', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _purple, foregroundColor: Colors.white),
            onPressed: () async {
              final size = int.tryParse(sizeCtrl.text.trim());
              if (size == null || justCtrl.text.trim().isEmpty) return;
              try {
                await _repo.requestFleetExtension(requestedSize: size, justification: justCtrl.text.trim());
                if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demande envoyée !'))); }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    ),
  );
}

// ── Driver tile ───────────────────────────────────────────────────────────────
class _DriverTile extends StatelessWidget {
  final Map<String, dynamic> driver;
  const _DriverTile({required this.driver});

  Color get _statusColor {
    final s = driver['ambassadorStatus'] as String? ?? '';
    final active = driver['isActive'] as bool? ?? false;
    if (s == 'ACTIVE' && active) return Colors.green;
    if (s == 'PENDING') return Colors.orange;
    if (s == 'REJECTED') return Colors.red;
    return Colors.grey;
  }

  String get _statusLabel {
    final s = driver['ambassadorStatus'] as String? ?? '';
    final active = driver['isActive'] as bool? ?? false;
    if (s == 'ACTIVE' && active) return 'Actif';
    if (s == 'ACTIVE' && !active) return 'Suspendu';
    if (s == 'PENDING') return 'En attente';
    if (s == 'REJECTED') return 'Refusé';
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final courses = (driver['deliveredCourses'] as num?)?.toInt() ?? 0;
    final rating  = (driver['avgRating'] as num?)?.toDouble();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)]),
      child: Row(children: [
        CircleAvatar(
          backgroundColor: _purple.withValues(alpha: 0.12),
          child: Text((driver['name'] ?? '?').toString()[0].toUpperCase(), style: const TextStyle(color: _purple, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(driver['name'] ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          Text(driver['phone'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 3),
          Row(children: [
            Text('$courses courses', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            if (rating != null) ...[
              const SizedBox(width: 8),
              const Icon(Icons.star, size: 12, color: Colors.amber),
              Text(rating.toStringAsFixed(1), style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ]),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: _statusColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
          child: Text(_statusLabel, style: TextStyle(color: _statusColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}
