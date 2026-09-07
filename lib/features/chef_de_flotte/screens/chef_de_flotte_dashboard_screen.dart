import '../../../core/error/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/network_error_widget.dart';
import '../data/chef_de_flotte_repository.dart';
import '../../../core/utils/dem_layout.dart';
import '../../../shared/widgets/pressable.dart';
import '../utils/format.dart';

class ChefDeFlotteDashboardScreen extends StatefulWidget {
  const ChefDeFlotteDashboardScreen({super.key});
  @override
  State<ChefDeFlotteDashboardScreen> createState() => _State();
}

class _State extends State<ChefDeFlotteDashboardScreen>
    with SingleTickerProviderStateMixin {
  final _repo = ChefDeFlotteRepository(ApiClient.dio);
  late TabController _tabs;

  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _drivers = [];
  bool _loadingStats = true;
  bool _loadingDrivers = true;
  String? _statsError;
  String? _driversError;
  String _driverFilter = 'all';
  String _driverSort = 'recent';
  String _statsPeriod = 'today';

  static const List<(String, String)> _statsPeriods = [
    ('today', 'Jour'),
    ('week', 'Semaine'),
    ('month', 'Mois'),
    ('sixMonths', '6 mois'),
  ];

  static const Map<String, String> _sortLabels = {
    'recent': 'Récents',
    'courses': 'Plus de courses',
    'rating': 'Meilleure note',
    'active': 'Plus actif aujourd\'hui',
  };

  List<Map<String, dynamic>> get _sortedDrivers {
    if (_driverSort == 'recent') return _drivers; // déjà l'ordre du serveur
    final key = switch (_driverSort) {
      'courses' => 'deliveredCourses',
      'rating' => 'avgRating',
      'active' => 'activeSecondsToday',
      _ => 'deliveredCourses',
    };
    double valueOf(Map<String, dynamic> d) =>
        (d[key] as num?)?.toDouble() ?? -1;
    return [..._drivers]..sort((a, b) => valueOf(b).compareTo(valueOf(a)));
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadStats();
    _loadDrivers();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    if (mounted)
      setState(() {
        _loadingStats = true;
        _statsError = null;
      });
    try {
      final s = await _repo.getStats();
      if (mounted)
        setState(() {
          _stats = s;
          _loadingStats = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _loadingStats = false;
          _statsError = friendlyError(e);
        });
    }
  }

  Future<void> _loadDrivers() async {
    if (mounted)
      setState(() {
        _loadingDrivers = true;
        _driversError = null;
      });
    try {
      final filter = _driverFilter == 'all' ? null : _driverFilter;
      final list = await _repo.getDrivers(status: filter);
      if (mounted)
        setState(() {
          _drivers = list;
          _loadingDrivers = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _loadingDrivers = false;
          _driversError = friendlyError(e);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      body: RefreshIndicator(
        color: AppColors.primaryMid,
        onRefresh: () => Future.wait([_loadStats(), _loadDrivers()]),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: DemLayout.isTablet(context) ? 200.0 : 160.0,
              pinned: true,
              backgroundColor: AppColors.primaryDark,
              foregroundColor: Colors.white,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: AppColors.gradientSplash,
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 60, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'Mon espace Chef de flotte',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: DemLayout.isTablet(context) ? 13.0 : 12.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'DEM Chef de flotte',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: DemLayout.isTablet(context) ? 26.0 : 22.0,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.map_outlined),
                  tooltip: 'Carte de la flotte',
                  onPressed: () => context.push('/chef-de-flotte/fleet-map'),
                ),
                IconButton(
                  icon: const Icon(Icons.person_outline),
                  tooltip: 'Mon profil',
                  onPressed: () => context.push('/chef-de-flotte/profile'),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Ajouter un livreur',
                  onPressed: () => context
                      .push('/chef-de-flotte/add-driver')
                      .then((_) => _loadDrivers()),
                ),
              ],
            ),

            // Stats cards
            SliverToBoxAdapter(
              child: _loadingStats
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primaryMid,
                        ),
                      ),
                    )
                  : _statsError != null
                  ? NetworkErrorWidget(
                      message: _statsError!,
                      onRetry: _loadStats,
                    )
                  : _buildStats(),
            ),

            // Drivers section header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Text(
                      'Mes livreurs',
                      style: TextStyle(
                        color: const Color.fromARGB(179, 0, 143, 252),
                        fontSize: DemLayout.isTablet(context) ? 18.0 : 16.0,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.swap_vert_rounded,
                        size: 20,
                        color: AppColors.primaryMid,
                      ),
                      tooltip: 'Trier',
                      initialValue: _driverSort,
                      onSelected: (v) => setState(() => _driverSort = v),
                      itemBuilder: (ctx) => [
                        for (final entry in _sortLabels.entries)
                          PopupMenuItem(
                            value: entry.key,
                            child: Row(
                              children: [
                                if (_driverSort == entry.key)
                                  const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: AppColors.primaryMid,
                                  )
                                else
                                  const SizedBox(width: 16),
                                const SizedBox(width: 8),
                                Text(entry.value),
                              ],
                            ),
                          ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18),
                      onPressed: _loadDrivers,
                    ),
                  ],
                ),
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
                      ('all', 'Tous'),
                      ('active', 'Actifs'),
                      ('pending', 'En attente'),
                      ('rejected', 'Refusés'),
                      ('suspended', 'Suspendus'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(
                            f.$2,
                            style: TextStyle(
                              fontSize: 12,
                              color: _driverFilter == f.$1
                                  ? Colors.white
                                  : AppColors.primaryMid,
                              fontWeight: _driverFilter == f.$1
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          selected: _driverFilter == f.$1,
                          onSelected: (_) {
                            setState(() => _driverFilter = f.$1);
                            _loadDrivers();
                          },
                          selectedColor: AppColors.primaryMid,
                          backgroundColor: Colors.white,
                          showCheckmark: false,
                          side: BorderSide(
                            color: _driverFilter == f.$1
                                ? AppColors.primaryMid
                                : AppColors.primary.withValues(alpha: 0.40),
                            width: 1.5,
                          ),
                          elevation: 0,
                          pressElevation: 0,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Driver list
            _loadingDrivers
                ? const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primaryMid,
                        ),
                      ),
                    ),
                  )
                : _driversError != null
                ? NetworkErrorWidget(
                    message: _driversError!,
                    onRetry: _loadDrivers,
                    sliver: true,
                  )
                : _drivers.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.group_outlined,
                            color: Colors.grey,
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Aucun livreur',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Ajouter un livreur'),
                            onPressed: () => context
                                .push('/chef-de-flotte/add-driver')
                                .then((_) => _loadDrivers()),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryMid,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _DriverTile(driver: _sortedDrivers[i]),
                        childCount: _sortedDrivers.length,
                      ),
                    ),
                  ),
          ],
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              AppColors.primary,
              AppColors.primaryMid,
              AppColors.primaryDark,
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.40),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context
                .push('/chef-de-flotte/add-driver')
                .then((_) => _loadDrivers()),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Ajouter livreur',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStats() {
    final s = _stats!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              _StatCard(
                label: 'Flotte active',
                value: '${s['activeCount'] ?? 0}',
                icon: Icons.check_circle_outline,
                color: Colors.green,
              ),
              const SizedBox(width: 10),
              _StatCard(
                label: 'En attente',
                value: '${s['pendingCount'] ?? 0}',
                icon: Icons.hourglass_top_rounded,
                color: Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatCard(
                label: 'Courses total',
                value: '${s['totalCourses'] ?? 0}',
                icon: Icons.motorcycle,
                color: AppColors.primaryMid,
              ),
              const SizedBox(width: 10),
              _StatCard(
                label: 'Alertes',
                value: '${s['alertsCount'] ?? 0}',
                icon: Icons.warning_amber_rounded,
                color: ((s['alertsCount'] as num?) ?? 0) > 0
                    ? Colors.red
                    : Colors.grey,
                onTap: () => context.push('/chef-de-flotte/incidents'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Pressable(
            onTap: () => context.push('/chef-de-flotte/fleet-extensions'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.directions_bike,
                    color: AppColors.primaryMid,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Flotte : ${s['fleetSize'] ?? 0} / ${s['fleetMax'] ?? 10} motos',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  if ((s['fleetSize'] ?? 0) >= (s['fleetMax'] ?? 10))
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryMid.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '+ Extension',
                        style: TextStyle(
                          color: AppColors.primaryMid,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.primaryMid,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _PeriodStatsCard(
            periods: _statsPeriods,
            selected: _statsPeriod,
            onSelect: (p) => setState(() => _statsPeriod = p),
            data:
                (s['statsByPeriod'] as Map?)?[_statsPeriod] as Map? ?? const {},
          ),
          if (!((s['isFleetReady'] as bool?) ?? true))
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Minimum 3 livreurs actifs requis pour être opérationnel.',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
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

// ── Carte tendance par période ──────────────────────────────────────────────
// Le sélecteur période (jour/semaine/mois/6 mois) existait déjà côté détail
// livreur mais jamais côté flotte entière — sans ça, un chef de flotte ne
// voyait qu'un total brut sans savoir si sa flotte progresse ou régresse.
class _PeriodStatsCard extends StatelessWidget {
  final List<(String, String)> periods;
  final String selected;
  final ValueChanged<String> onSelect;
  final Map data;
  const _PeriodStatsCard({
    required this.periods,
    required this.selected,
    required this.onSelect,
    required this.data,
  });

  (IconData, Color, String)? _trend(num current, num previous) {
    if (previous == 0) {
      if (current == 0) return null;
      return (Icons.trending_up, Colors.green, 'Nouveau');
    }
    final pct = ((current - previous) / previous * 100).round();
    if (pct == 0) return (Icons.trending_flat, Colors.grey, 'Stable');
    return pct > 0
        ? (Icons.trending_up, Colors.green, '+$pct%')
        : (Icons.trending_down, Colors.red, '$pct%');
  }

  @override
  Widget build(BuildContext context) {
    final courses = (data['courses'] as num?) ?? 0;
    final earnings = (data['earnings'] as num?) ?? 0;
    // Frais DEM déjà déduits de `earnings` — signalé pour comprendre l'écart
    // avec le tarif affiché au client (matrice zone/EXPRESS, ou grille de
    // commissions pour une tournée).
    final demFee = (data['demFee'] as num?) ?? 0;
    final previousCourses = (data['previousCourses'] as num?) ?? 0;
    final trend = _trend(courses, previousCourses);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final p in periods)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      p.$2,
                      style: TextStyle(
                        fontSize: 11,
                        color: selected == p.$1
                            ? Colors.white
                            : AppColors.primaryMid,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    selected: selected == p.$1,
                    onSelected: (_) => onSelect(p.$1),
                    selectedColor: AppColors.primaryMid,
                    backgroundColor: const Color(0xFFF1F5F9),
                    showCheckmark: false,
                    elevation: 0,
                    pressElevation: 0,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    '$courses course${courses > 1 ? 's' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (trend != null) ...[
                    const SizedBox(width: 8),
                    Icon(trend.$1, size: 14, color: trend.$2),
                    const SizedBox(width: 2),
                    Text(
                      trend.$3,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: trend.$2,
                      ),
                    ),
                  ],
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${earnings.round()} FCFA',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryMid,
                    ),
                  ),
                  if (demFee > 0)
                    Text(
                      '(dont ${demFee.round()} FCFA de frais DEM)',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                ],
              ),
            ],
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
  final VoidCallback? onTap;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => Expanded(
    child: Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                if (onTap != null) ...[
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.grey.shade300,
                    size: 16,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Driver tile ───────────────────────────────────────────────────────────────
class _DriverTile extends StatelessWidget {
  final Map<String, dynamic> driver;
  const _DriverTile({required this.driver});

  bool get _hasName => (driver['name'] as String?)?.trim().isNotEmpty == true;

  String get _avatarLetter {
    if (_hasName) return (driver['name'] as String).trim()[0].toUpperCase();
    final phone = driver['phone'] as String?;
    return (phone != null && phone.isNotEmpty)
        ? phone[phone.startsWith('+') ? 1 : 0]
        : '?';
  }

  Color get _statusColor {
    final s = driver['chefDeFlotteStatus'] as String? ?? '';
    final active = driver['isActive'] as bool? ?? false;
    if (s == 'ACTIVE' && active) return Colors.green;
    if (s == 'PENDING') return Colors.orange;
    if (s == 'REJECTED') return Colors.red;
    return Colors.grey;
  }

  String get _statusLabel {
    final s = driver['chefDeFlotteStatus'] as String? ?? '';
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
    final rating = (driver['avgRating'] as num?)?.toDouble();
    final activeSeconds = (driver['activeSecondsToday'] as num?)?.toInt() ?? 0;
    final id = driver['id'] as String?;
    return Pressable(
      onTap: id == null
          ? null
          : () => context.push('/chef-de-flotte/drivers/$id'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.primaryMid.withValues(alpha: 0.12),
              child: Text(
                _avatarLetter,
                style: const TextStyle(
                  color: AppColors.primaryMid,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Numéro toujours en repère principal — le nom (quand
                  // renseigné) vient en dessous, pas l'inverse : un chef de
                  // flotte identifie d'abord ses livreurs par numéro.
                  Text(
                    (driver['phone'] ?? '—').toString(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  if (_hasName)
                    Text(
                      driver['name'].toString(),
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        '$courses courses',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                      if (rating != null) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.star, size: 12, color: Colors.amber),
                        Text(
                          rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                      if (activeSeconds > 0) ...[
                        const SizedBox(width: 8),
                        // Zone de tap dédiée — n'ouvre pas la fiche livreur
                        // (comme le reste de la tuile) mais un popup dédié
                        // au temps en ligne, filtrable jour/semaine/mois.
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: id == null
                              ? null
                              : () => showOnlineTimeDialog(
                                  context,
                                  driverId: id,
                                  driverLabel: _hasName
                                      ? driver['name'].toString()
                                      : (driver['phone'] ?? '').toString(),
                                ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.timer_outlined,
                                size: 12,
                                color: AppColors.primaryMid,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                formatActiveDuration(activeSeconds),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.primaryMid,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _statusLabel,
                style: TextStyle(
                  color: _statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey.shade300,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Popup "temps en ligne" — filtrable jour/semaine/mois ────────────────────
// Ouvert au tap sur le temps en ligne d'une tuile (voir _DriverTile), plutôt
// que la navigation habituelle vers la fiche livreur. Réutilise
// statsByPeriod[period].activeSeconds, déjà calculé côté backend pour la
// fiche détail (voir chefs_de_flotte.service.js:getDriverDetail) — même
// source que le récap courses/gains par période.
Future<void> showOnlineTimeDialog(
  BuildContext context, {
  required String driverId,
  required String driverLabel,
}) {
  return showDialog(
    context: context,
    builder: (_) =>
        _OnlineTimeDialog(driverId: driverId, driverLabel: driverLabel),
  );
}

class _OnlineTimeDialog extends StatefulWidget {
  final String driverId;
  final String driverLabel;
  const _OnlineTimeDialog({required this.driverId, required this.driverLabel});

  @override
  State<_OnlineTimeDialog> createState() => _OnlineTimeDialogState();
}

class _OnlineTimeDialogState extends State<_OnlineTimeDialog> {
  final _repo = ChefDeFlotteRepository(ApiClient.dio);
  String _period = 'today';
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _statsByPeriod;

  static const _periods = [
    ('today', 'Jour'),
    ('week', 'Semaine'),
    ('month', 'Mois'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _repo.getDriverDetail(widget.driverId);
      if (!mounted) return;
      setState(() {
        _statsByPeriod = (detail['statsByPeriod'] as Map?)
            ?.cast<String, dynamic>();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de charger le temps en ligne.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final periodStats = (_statsByPeriod?[_period] as Map?)
        ?.cast<String, dynamic>();
    final activeSeconds = (periodStats?['activeSeconds'] as num?)?.toInt() ?? 0;
    final periodLabel = _periods.firstWhere((p) => p.$1 == _period).$2;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primaryMid.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.timer_outlined,
                    color: AppColors.primaryMid,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Temps en ligne',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        widget.driverLabel,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: _periods.map((p) {
                final selected = _period == p.$1;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _period = p.$1),
                    child: Container(
                      margin: EdgeInsets.only(
                        right: p.$1 != _periods.last.$1 ? 6 : 0,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primaryMid
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        p.$2,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: CircularProgressIndicator(color: AppColors.primaryMid),
                ),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              )
            else
              Center(
                child: Column(
                  children: [
                    Text(
                      formatActiveDuration(activeSeconds),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryMid,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'en ligne — ${periodLabel.toLowerCase()}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
