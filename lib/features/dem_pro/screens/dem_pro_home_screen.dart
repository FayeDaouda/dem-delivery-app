import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/api/api_client.dart';
import '../../../core/router/app_startup_notifier.dart';
import '../../../core/storage/auth_storage.dart';
import '../../deliveries/data/orders_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../data/dem_pro_repository.dart';
import '../theme/dem_pro_colors.dart';
import '../widgets/dem_pro_nav_bar.dart';
import 'dem_pro_batch_tracking_screen.dart' show DemProBatchTrackingScreen;

const _sectorLabels = {
  'commerce':     'Commerce',
  'restauration': 'Restauration',
  'services':     'Services',
  'artisanat':    'Artisanat',
  'autre':        'Autre',
};

const _volumeLabels = {
  'low':    '1 à 4 livraisons / semaine',
  'medium': '5 à 8 livraisons / semaine',
  'high':   '9 ou plus / semaine',
};

String _fcfa(num value) {
  final s = value.round().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '$buf FCFA';
}

const _dayNames   = ['Lundi','Mardi','Mercredi','Jeudi','Vendredi','Samedi','Dimanche'];
const _monthNames = ['janvier','février','mars','avril','mai','juin','juillet',
                     'août','septembre','octobre','novembre','décembre'];

// ── Filtre livraisons ─────────────────────────────────────────────────────────
enum _OrderFilter {
  all('Toutes'),
  active('En cours'),
  delivered('Livrées'),
  cancelled('Annulées');
  final String label;
  const _OrderFilter(this.label);
}

enum _ViewType { orders, batches }

// ── Helpers statut tournée ────────────────────────────────────────────────────
String _batchStatusLabel(String s) => switch (s) {
  'PENDING'     => 'En attente',
  'ACCEPTED'    => 'Livreur assigné',
  'IN_PROGRESS' => 'En cours',
  'COMPLETED'   => 'Terminée',
  'CANCELLED'   => 'Annulée',
  'SCHEDULED'   => 'Programmée',
  _             => s,
};

Color _batchStatusColor(String s) => switch (s) {
  'PENDING'     => DemProColors.warning,
  'ACCEPTED'    => DemProColors.accent,
  'IN_PROGRESS' => DemProColors.accent,
  'COMPLETED'   => DemProColors.success,
  'CANCELLED'   => DemProColors.danger,
  'SCHEDULED'   => DemProColors.muted,
  _             => DemProColors.muted,
};

// ── Helpers statut ────────────────────────────────────────────────────────────
bool _isActiveStatus(String s) =>
    const {'PENDING', 'ACCEPTED', 'PICKED_UP', 'IN_TRANSIT'}.contains(s);

String _statusLabel(String s) => switch (s) {
  'PENDING'    => 'En attente',
  'ACCEPTED'   => 'Acceptée',
  'PICKED_UP'  => 'Récupéré',
  'IN_TRANSIT' => 'En route',
  'DELIVERED'  => 'Livré',
  'CANCELLED'  => 'Annulé',
  _            => s,
};

Color _statusColor(String s) => switch (s) {
  'PENDING'    => DemProColors.warning,
  'ACCEPTED'   => DemProColors.accent,
  'PICKED_UP'  => DemProColors.accent,
  'IN_TRANSIT' => DemProColors.accent,
  'DELIVERED'  => DemProColors.success,
  'CANCELLED'  => DemProColors.danger,
  _            => DemProColors.muted,
};

String _shortAddress(String addr) => addr.split(',').first.trim();

void _navigateToOrder(BuildContext context, Map<String, dynamic> order) {
  final status = order['status'] as String? ?? '';
  if (status == 'PENDING') {
    context.push('/dem-pro/orders/confirmation', extra: order);
  } else if (const {'ACCEPTED', 'PICKED_UP', 'IN_TRANSIT'}.contains(status)) {
    final driverId = (order['driver'] as Map?)?['id'] as String?
        ?? order['driverId'] as String? ?? '';
    context.push('/dem-pro/orders/tracking', extra: {
      'orderId': order['id'],
      'driverId': driverId,
      'initialOrder': order,
    });
  }
}

String _driverInitials(String? name) {
  if (name == null || name.isEmpty) return '?';
  final p = name.trim().split(RegExp(r'\s+'));
  return p.length >= 2 ? '${p[0][0]}${p[1][0]}'.toUpperCase() : p[0][0].toUpperCase();
}

String _timeAgo(String? iso) {
  if (iso == null) return '';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1)  return 'À l\'instant';
  if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes}min';
  if (diff.inHours < 24)   return 'Il y a ${diff.inHours}h';
  return 'Il y a ${diff.inDays}j';
}

String _formatDateTime(String? iso) {
  final dt = iso != null ? DateTime.tryParse(iso)?.toLocal() : null;
  if (dt == null) return '';
  const m = ['jan.','fév.','mars','avr.','mai','juin','juil.','août','sep.','oct.','nov.','déc.'];
  const d = ['Lun.','Mar.','Mer.','Jeu.','Ven.','Sam.','Dim.'];
  final h = dt.hour.toString().padLeft(2, '0');
  final mn = dt.minute.toString().padLeft(2, '0');
  return '${d[dt.weekday - 1]} ${dt.day} ${m[dt.month - 1]} · $h:$mn';
}

// ── Palette adaptative clair/sombre ──────────────────────────────────────────

class _T {
  final bool dark;
  const _T(this.dark);

  Color get scaffoldBg => dark ? DemProColors.bg    : const Color(0xFFF8FAFC);
  Color get cardBg     => dark ? DemProColors.bg2   : Colors.white;
  Color get cardBg2    => dark ? DemProColors.bg3   : const Color(0xFFF1F5F9);
  Color get cardBg3    => dark ? DemProColors.bg4   : const Color(0xFFE8EFF6);
  Color get border     => dark ? DemProColors.bg3   : const Color(0xFFE2E8F0);
  Color get text       => dark ? DemProColors.text  : const Color(0xFF0F172A);
  Color get muted      => dark ? DemProColors.muted : const Color(0xFF64748B);

  List<Color> get statGradient => dark
      ? [DemProColors.bg3, DemProColors.bg4]
      : [const Color(0xFFEFF6FF), const Color(0xFFDCEFFB)];

  List<Color> get headerCardGradient => dark
      ? [DemProColors.bg3, DemProColors.bg4]
      : [Colors.white, const Color(0xFFEFF6FF)];
}

// ─────────────────────────────────────────────────────────────────────────────

class DemProHomeScreen extends StatefulWidget {
  const DemProHomeScreen({super.key});
  @override
  State<DemProHomeScreen> createState() => _State();
}

class _State extends State<DemProHomeScreen> with WidgetsBindingObserver {
  int  _currentIndex = 0;
  bool _darkMode     = true;

  final _demProRepo = DemProRepository(ApiClient.dio);
  final _livraisonsKey = GlobalKey<_LivraisonsTabState>();

  Map<String, dynamic>? _user;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _activeOrders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ProfileRepository().getMe(),
        _demProRepo.getMyStats(),
        _demProRepo.getMyOrders(),
      ]);
      if (!mounted) return;
      final orders = results[2] as List<Map<String, dynamic>>;
      final active = orders.where((o) {
        final s = o['status'] as String? ?? '';
        return const {'PENDING', 'ACCEPTED', 'PICKED_UP', 'IN_TRANSIT'}.contains(s);
      }).toList();
      setState(() {
        _user = results[0] as Map<String, dynamic>;
        _stats = results[1] as Map<String, dynamic>;
        _activeOrders = active;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleLogout() async {
    await AuthStorage.clear();
    appStartupNotifier.markLoggedOut();
    if (mounted) context.go('/phone');
  }

  @override
  Widget build(BuildContext context) {
    final t = _T(_darkMode);
    return Scaffold(
      backgroundColor: t.scaffoldBg,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _AccueilTab(
            user: _user, stats: _stats, loading: _loading,
            activeOrders: _activeOrders,
            onRefresh: _load, t: t,
          ),
          _LivraisonsTab(key: _livraisonsKey, t: t),
          _AdressesTab(t: t),
          _FinancesTab(t: t),
          _CompteTab(
            user: _user, onLogout: _handleLogout, t: t,
            darkMode: _darkMode,
            onThemeToggle: () => setState(() => _darkMode = !_darkMode),
            onRefresh: _load,
          ),
        ],
      ),
      floatingActionButton: switch (_currentIndex) {
        1 => FloatingActionButton(
              backgroundColor: DemProColors.accent,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onPressed: () => context.push('/dem-pro/orders/create'),
              child: const Icon(Icons.add, size: 28),
            ),
        _ => null,
      },
      bottomNavigationBar: DemProNavBar(
        currentIndex: _currentIndex,
        onTap: (i) {
          setState(() => _currentIndex = i);
          if (i == 0) _load();
          if (i == 1) _livraisonsKey.currentState?._loadOrders();
        },
        darkMode: _darkMode,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Onglet Accueil
// ─────────────────────────────────────────────────────────────────────────────

class _AccueilTab extends StatelessWidget {
  final Map<String, dynamic>? user;
  final Map<String, dynamic>? stats;
  final bool loading;
  final List<Map<String, dynamic>> activeOrders;
  final Future<void> Function() onRefresh;
  final _T t;
  const _AccueilTab({
    required this.user, required this.stats,
    required this.loading, required this.activeOrders,
    required this.onRefresh, required this.t,
  });

  void _goToActiveOrder(BuildContext context, Map<String, dynamic> o) {
    final status = o['status'] as String? ?? '';
    if (status == 'PENDING') {
      context.push('/dem-pro/orders/confirmation', extra: o);
    } else {
      final driverId = (o['driver'] as Map?)?['id'] as String?
          ?? o['driverId'] as String? ?? '';
      context.push('/dem-pro/orders/tracking', extra: {
        'orderId': o['id'],
        'driverId': driverId,
        'initialOrder': o,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final businessName = (user?['proBusinessName'] as String?)?.trim();
    final rawName      = (user?['name'] as String? ?? '').trim();
    final firstName    = rawName.isNotEmpty ? rawName.split(RegExp(r'\s+')).first : '';
    final greeting     = firstName.isNotEmpty ? 'Bonjour $firstName 👋' : 'Bonjour 👋';

    final delivered  = (stats?['deliveriesToday']?['completed']  as num?)?.toInt() ?? 0;
    final inProgress = (stats?['deliveriesToday']?['inProgress'] as num?)?.toInt() ?? 0;
    final spentToday = (stats?['spendingToday'] as num?) ?? 0;
    final spentMonth = (stats?['spendingMonth'] as num?) ?? 0;

    final now      = DateTime.now();
    final dateStr  = '${_dayNames[now.weekday - 1]} ${now.day} ${_monthNames[now.month - 1]}';

    return SafeArea(
      child: RefreshIndicator(
        color: DemProColors.accent,
        backgroundColor: t.cardBg,
        onRefresh: onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Header ──────────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tableau de bord',
                          style: TextStyle(color: t.muted, fontSize: 12),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          greeting,
                          style: const TextStyle(
                            color: DemProColors.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _ProAvatar(
                              avatarUrl: user?['avatar'] as String?,
                              businessName: businessName,
                              size: 40,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                businessName?.isNotEmpty == true ? businessName! : 'Mon entreprise',
                                style: TextStyle(
                                  color: t.text,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const _ProBadge(),
                      if (activeOrders.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _ActiveOrderIcon(
                          count: activeOrders.length,
                          onTap: () => _goToActiveOrder(context, activeOrders.first),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Carte résumé ─────────────────────────────────────────────
              if (loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator(color: DemProColors.accent)),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: t.statGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: DemProColors.accent.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // En-tête avec date dynamique
                      Row(children: [
                        const Icon(Icons.two_wheeler, color: DemProColors.accent, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Livraisons — $dateStr',
                          style: TextStyle(
                            color: t.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 14),

                      // Grandes stats livrées / en cours
                      Row(children: [
                        Expanded(
                          child: _BigStatBox(
                            value: '$delivered',
                            label: 'Livrées',
                            color: DemProColors.success,
                            t: t,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _BigStatBox(
                            value: '$inProgress',
                            label: 'En cours',
                            color: DemProColors.warning,
                            t: t,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 14),

                      // Dépenses en 2 mini-cards distinctes
                      Row(children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: t.cardBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Dépenses aujourd\'hui',
                                  style: TextStyle(color: t.muted, fontSize: 10),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _fcfa(spentToday),
                                  style: TextStyle(
                                    color: t.text,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: t.cardBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Dépenses ce mois',
                                  style: TextStyle(color: t.muted, fontSize: 10),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _fcfa(spentMonth),
                                  style: TextStyle(
                                    color: t.text,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              const SizedBox(height: 20),

              // ── Actions ──────────────────────────────────────────────────
              Row(children: [
                Expanded(
                  child: _ActionButton(
                    label: 'Livraison',
                    icon: Icons.two_wheeler,
                    filled: true,
                    onTap: () => context.push('/dem-pro/orders/create'),
                    t: t,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    label: 'Programmer',
                    icon: Icons.schedule,
                    filled: false,
                    onTap: () => context.push('/dem-pro/orders/create?scheduled=true'),
                    t: t,
                  ),
                ),
              ]),
              const SizedBox(height: 28),

              // ── En cours ─────────────────────────────────────────────────
              _SectionLabel(label: 'EN COURS', t: t),
              const SizedBox(height: 12),
              _EnCoursEmpty(
                onOrder: () => context.push('/dem-pro/orders/create'),
                t: t,
              ),
              const SizedBox(height: 24),

              // ── Historique récent ─────────────────────────────────────────
              _SectionLabel(label: 'HISTORIQUE RÉCENT', t: t),
              const SizedBox(height: 12),
              _HistoriqueEmpty(t: t),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Onglet Compte
// ─────────────────────────────────────────────────────────────────────────────

class _CompteTab extends StatefulWidget {
  final Map<String, dynamic>? user;
  final VoidCallback onLogout;
  final VoidCallback onThemeToggle;
  final bool darkMode;
  final _T t;
  final Future<void> Function() onRefresh;
  const _CompteTab({
    required this.user, required this.onLogout,
    required this.onThemeToggle, required this.darkMode, required this.t,
    required this.onRefresh,
  });
  @override
  State<_CompteTab> createState() => _CompteTabState();
}

class _CompteTabState extends State<_CompteTab> {
  bool _uploading = false;

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 512, imageQuality: 80);
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(picked.path, filename: picked.name),
        'field': 'avatar',
      });
      await ApiClient.dio.post('/users/driver/documents', data: formData);
      await widget.onRefresh();
    } catch (e) {
      debugPrint('[AVATAR UPLOAD] error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Échec de l\'upload. Réessayez.')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _editField(String label, String currentValue, String fieldKey) async {
    final ctrl = TextEditingController(text: currentValue);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: widget.t.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Modifier $label', style: TextStyle(color: widget.t.text, fontSize: 16, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: widget.t.text),
          decoration: InputDecoration(
            hintText: label,
            hintStyle: TextStyle(color: widget.t.muted),
            filled: true,
            fillColor: widget.t.cardBg2,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Annuler', style: TextStyle(color: widget.t.muted))),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Enregistrer', style: TextStyle(color: DemProColors.accent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || result == currentValue) return;
    try {
      await ApiClient.dio.patch('/users/me/profile', data: {fieldKey: result});
      await widget.onRefresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Échec de la mise à jour.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final user = widget.user;
    final businessName = (user?['proBusinessName'] as String?)?.trim();
    final name         = user?['name']  as String?;
    final phone        = user?['phone'] as String?;
    final email        = user?['email'] as String?;
    final sector       = user?['proSector']       as String?;
    final volume       = user?['proWeeklyVolume'] as String?;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Carte entreprise ──────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: t.headerCardGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: DemProColors.accent.withValues(alpha: 0.15)),
              ),
              child: Row(children: [
                GestureDetector(
                  onTap: _uploading ? null : _pickAndUploadAvatar,
                  child: Stack(
                    children: [
                      _ProAvatar(
                        avatarUrl: user?['avatar'] as String?,
                        businessName: businessName,
                        size: 56,
                      ),
                      Positioned(
                        bottom: 0, right: 0,
                        child: Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color: DemProColors.accent,
                            shape: BoxShape.circle,
                            border: Border.all(color: t.cardBg, width: 2),
                          ),
                          child: _uploading
                              ? const Padding(
                                  padding: EdgeInsets.all(3),
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5),
                                )
                              : const Icon(Icons.camera_alt, color: Colors.white, size: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => _editField('Nom entreprise', businessName ?? '', 'proBusinessName'),
                        child: Row(children: [
                          Expanded(child: Text(
                            businessName?.isNotEmpty == true ? businessName! : 'Mon entreprise',
                            style: TextStyle(color: t.text, fontSize: 17, fontWeight: FontWeight.w800),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          )),
                          Icon(Icons.edit_outlined, color: t.muted, size: 14),
                        ]),
                      ),
                      const SizedBox(height: 4),
                      const _ProBadge(),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),

            _SectionLabel(label: 'INFORMATIONS', t: t),
            const SizedBox(height: 12),
            _InfoCard(
              t: t,
              children: [
                _EditableInfoRow(icon: Icons.person_outline, label: 'Responsable', value: name ?? '—', t: t,
                  onTap: () => _editField('Responsable', name ?? '', 'name')),
                _InfoRow(icon: Icons.phone_outlined, label: 'Téléphone', value: phone ?? '—', t: t),
                _EditableInfoRow(icon: Icons.email_outlined, label: 'Email', value: email?.isNotEmpty == true ? email! : '—', t: t,
                  onTap: () => _editField('Email', email ?? '', 'email')),
                _InfoRow(icon: Icons.category_outlined,  label: 'Secteur',     value: _sectorLabels[sector] ?? '—', t: t),
                _InfoRow(icon: Icons.bar_chart_outlined, label: 'Volume hebdo', value: _volumeLabels[volume] ?? '—', t: t, isLast: true),
              ],
            ),
            const SizedBox(height: 24),

            // ── Préférences ───────────────────────────────────────────────
            _SectionLabel(label: 'PRÉFÉRENCES', t: t),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: t.cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.border),
              ),
              child: Row(children: [
                Icon(
                  widget.darkMode ? Icons.dark_mode_outlined : Icons.wb_sunny_outlined,
                  color: DemProColors.accent,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.darkMode ? 'Mode sombre' : 'Mode clair',
                    style: TextStyle(color: t.text, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                Switch(
                  value: widget.darkMode,
                  onChanged: (_) => widget.onThemeToggle(),
                  activeThumbColor: Colors.white,
                  activeTrackColor: DemProColors.accent,
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: t.border,
                ),
              ]),
            ),
            const SizedBox(height: 24),

            // ── Déconnexion ───────────────────────────────────────────────
            _LogoutButton(onTap: widget.onLogout, t: t),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets locaux
// ─────────────────────────────────────────────────────────────────────────────

class _ProBadge extends StatelessWidget {
  const _ProBadge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: DemProColors.accent.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text('DEM PRO',
      style: TextStyle(
        color: DemProColors.accent,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      )),
  );
}

class _ActiveOrderIcon extends StatefulWidget {
  final int count;
  final VoidCallback onTap;
  const _ActiveOrderIcon({required this.count, required this.onTap});
  @override
  State<_ActiveOrderIcon> createState() => _ActiveOrderIconState();
}

class _ActiveOrderIconState extends State<_ActiveOrderIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: widget.onTap,
    child: AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: DemProColors.accent.withValues(alpha: 0.12 + _ctrl.value * 0.08),
          shape: BoxShape.circle,
          border: Border.all(
            color: DemProColors.accent.withValues(alpha: 0.4 + _ctrl.value * 0.3),
            width: 1.5,
          ),
        ),
        child: child,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.two_wheeler, color: DemProColors.accent, size: 20),
          if (widget.count > 1)
            Positioned(
              top: 2, right: 2,
              child: Container(
                width: 14, height: 14,
                decoration: const BoxDecoration(
                  color: DemProColors.accent,
                  shape: BoxShape.circle,
                ),
                child: Center(child: Text(
                  '${widget.count}',
                  style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800),
                )),
              ),
            ),
        ],
      ),
    ),
  );
}

class _ProAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String? businessName;
  final double size;
  const _ProAvatar({this.avatarUrl, this.businessName, this.size = 40});

  String get _initials {
    final name = (businessName ?? '').trim();
    if (name.isEmpty) return 'P';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = avatarUrl != null && avatarUrl!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: DemProColors.accent.withValues(alpha: 0.15),
        border: Border.all(color: DemProColors.accent.withValues(alpha: 0.3), width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasUrl
          ? Image.network(
              avatarUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  _initials,
                  style: TextStyle(
                    color: DemProColors.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: size * 0.38,
                  ),
                ),
              ),
            )
          : Center(
              child: Text(
                _initials,
                style: TextStyle(
                  color: DemProColors.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: size * 0.38,
                ),
              ),
            ),
    );
  }
}

// Grande stat dans la carte (livrées / en cours)
class _BigStatBox extends StatelessWidget {
  final String value, label;
  final Color color;
  final _T t;
  const _BigStatBox({required this.value, required this.label, required this.color, required this.t});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(children: [
      Text(
        value,
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w900,
          color: color,
          height: 1,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        label,
        style: TextStyle(
          color: t.muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ]),
  );
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;
  final _T t;
  const _ActionButton({required this.label, required this.icon, required this.filled, required this.onTap, required this.t});

  @override
  Widget build(BuildContext context) => Material(
    color: filled ? DemProColors.accent : Colors.transparent,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: filled ? null : Border.all(color: t.border),
        ),
        child: Column(children: [
          Icon(icon, color: filled ? Colors.white : DemProColors.accent, size: 22),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: filled ? Colors.white : t.text,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ]),
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final _T t;
  const _SectionLabel({required this.label, required this.t});
  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      color: t.muted,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
    ),
  );
}

// Empty state "EN COURS" avec micro CTA
class _EnCoursEmpty extends StatelessWidget {
  final VoidCallback onOrder;
  final _T t;
  const _EnCoursEmpty({required this.onOrder, required this.t});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
    decoration: BoxDecoration(
      color: t.cardBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: DemProColors.accent.withValues(alpha: 0.20)),
    ),
    child: Column(children: [
      Icon(Icons.two_wheeler, color: DemProColors.accent.withValues(alpha: 0.55), size: 30),
      const SizedBox(height: 10),
      Text(
        'Aucune livraison en cours',
        style: TextStyle(color: t.muted, fontSize: 13),
      ),
      const SizedBox(height: 14),
      GestureDetector(
        onTap: onOrder,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: DemProColors.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: DemProColors.accent.withValues(alpha: 0.30)),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Text(
              'Passez votre première commande',
              style: TextStyle(
                color: DemProColors.accent,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(width: 4),
            Icon(Icons.arrow_forward, color: DemProColors.accent, size: 14),
          ]),
        ),
      ),
    ]),
  );
}

// Empty state "HISTORIQUE" — neutre, différent de EN COURS
class _HistoriqueEmpty extends StatelessWidget {
  final _T t;
  const _HistoriqueEmpty({required this.t});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 28),
    decoration: BoxDecoration(
      color: t.cardBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: t.border),
    ),
    child: Column(children: [
      Icon(Icons.receipt_long_outlined, color: t.muted.withValues(alpha: 0.5), size: 28),
      const SizedBox(height: 10),
      Text(
        'Aucune livraison récente',
        style: TextStyle(color: t.muted, fontSize: 13),
      ),
      const SizedBox(height: 4),
      Text(
        'Votre historique apparaîtra ici',
        style: TextStyle(color: t.muted.withValues(alpha: 0.55), fontSize: 11),
      ),
    ]),
  );
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  final _T t;
  const _InfoCard({required this.children, required this.t});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: t.cardBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: t.border),
    ),
    child: Column(children: children),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final bool isLast;
  final _T t;
  const _InfoRow({required this.icon, required this.label, required this.value, required this.t, this.isLast = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      border: isLast ? null : Border(bottom: BorderSide(color: t.border)),
    ),
    child: Row(children: [
      Icon(icon, color: DemProColors.accent, size: 18),
      const SizedBox(width: 12),
      Expanded(child: Text(label, style: TextStyle(color: t.muted, fontSize: 13))),
      Text(value, style: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w600)),
    ]),
  );
}

class _EditableInfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final _T t;
  final VoidCallback onTap;
  const _EditableInfoRow({required this.icon, required this.label, required this.value, required this.t, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      child: Row(children: [
        Icon(icon, color: DemProColors.accent, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: TextStyle(color: t.muted, fontSize: 13))),
        Text(value, style: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        Icon(Icons.edit_outlined, color: t.muted, size: 14),
      ]),
    ),
  );
}

class _LogoutButton extends StatelessWidget {
  final VoidCallback onTap;
  final _T t;
  const _LogoutButton({required this.onTap, required this.t});
  @override
  Widget build(BuildContext context) => Material(
    color: t.cardBg,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.border),
        ),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.logout_outlined, color: DemProColors.danger, size: 18),
          SizedBox(width: 10),
          Text(
            'Se déconnecter',
            style: TextStyle(color: DemProColors.danger, fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ]),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Onglet Livraisons
// ─────────────────────────────────────────────────────────────────────────────

class _LivraisonsTab extends StatefulWidget {
  final _T t;
  const _LivraisonsTab({super.key, required this.t});
  @override
  State<_LivraisonsTab> createState() => _LivraisonsTabState();
}

class _LivraisonsTabState extends State<_LivraisonsTab> {
  late final DemProRepository _repo;

  // ── Livraisons ─────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _orders   = [];
  bool         _loadingOrders          = true;
  _OrderFilter _filter                 = _OrderFilter.all;

  // ── Tournées ───────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _batches  = [];
  bool         _loadingBatches         = false;

  _ViewType    _viewType               = _ViewType.orders;

  @override
  void initState() {
    super.initState();
    _repo = DemProRepository(ApiClient.dio);
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    if (!_loadingOrders) setState(() => _loadingOrders = true);
    try {
      final orders = await _repo.getMyOrders();
      if (!mounted) return;
      setState(() { _orders = orders; _loadingOrders = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingOrders = false);
    }
  }

  Future<void> _loadBatches() async {
    setState(() => _loadingBatches = true);
    try {
      final batches = await _repo.getMyBatches();
      if (!mounted) return;
      setState(() { _batches = batches; _loadingBatches = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingBatches = false);
    }
  }

  void _switchView(_ViewType v) {
    setState(() => _viewType = v);
    if (v == _ViewType.batches && _batches.isEmpty && !_loadingBatches) {
      _loadBatches();
    }
  }

  List<Map<String, dynamic>> get _activeOrders =>
      _orders.where((o) => _isActiveStatus(o['status'] as String)).toList();

  List<Map<String, dynamic>> get _historyOrders {
    if (_filter == _OrderFilter.delivered) {
      return _orders.where((o) => o['status'] == 'DELIVERED').toList();
    }
    if (_filter == _OrderFilter.cancelled) {
      return _orders.where((o) => o['status'] == 'CANCELLED').toList();
    }
    return _orders.where((o) => !_isActiveStatus(o['status'] as String)).toList();
  }

  int get _activeCount    => _activeOrders.length;
  int get _deliveredCount => _orders.where((o) => o['status'] == 'DELIVERED').length;
  int get _cancelledCount => _orders.where((o) => o['status'] == 'CANCELLED').length;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;

    return SafeArea(
      child: Column(
        children: [
          const SizedBox(height: 16),
          // ── Contenu ──────────────────────────────────────────────────────
          Expanded(child: _buildOrdersView(t)),
        ],
      ),
    );
  }

  // ── Vue Livraisons ─────────────────────────────────────────────────────────

  Widget _buildOrdersView(_T t) {
    if (_loadingOrders) {
      return Container(
        color: t.scaffoldBg,
        child: const Center(child: CircularProgressIndicator(color: DemProColors.accent)),
      );
    }

    final showActive    = _filter == _OrderFilter.all || _filter == _OrderFilter.active;
    final showHistory   = _filter != _OrderFilter.active;
    final activeToShow  = showActive  ? _activeOrders  : <Map<String, dynamic>>[];
    final historyToShow = showHistory ? _historyOrders : <Map<String, dynamic>>[];
    final isEmpty       = activeToShow.isEmpty && historyToShow.isEmpty;

    return RefreshIndicator(
      color: DemProColors.accent,
      backgroundColor: t.cardBg,
      onRefresh: _loadOrders,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FilterTabs(
              filter: _filter,
              totalCount:     _orders.length,
              activeCount:    _activeCount,
              deliveredCount: _deliveredCount,
              cancelledCount: _cancelledCount,
              t: t,
              onFilterChanged: (f) => setState(() => _filter = f),
            ),
            if (isEmpty)
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.55,
                child: _EmptyOrdersState(
                  t: t,
                  globallyEmpty: _orders.isEmpty,
                  onOrder: () => context.push('/dem-pro/orders/create'),
                ),
              )
            else ...[
              if (activeToShow.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: _SectionLabel(label: 'EN COURS', t: t),
                ),
                for (int i = 0; i < activeToShow.length; i++)
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, i < activeToShow.length - 1 ? 12 : 0),
                    child: _ActiveOrderCard(order: activeToShow[i], t: t),
                  ),
              ],
              if (historyToShow.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                  child: _SectionLabel(label: 'HISTORIQUE', t: t),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: t.cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: t.border),
                  ),
                  child: Column(
                    children: [
                      for (int i = 0; i < historyToShow.length; i++)
                        _HistoriqueRow(
                          order: historyToShow[i],
                          t: t,
                          isLast: i == historyToShow.length - 1,
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 90),
            ],
          ],
        ),
      ),
    );
  }

  // ── Vue Tournées ───────────────────────────────────────────────────────────

  Widget _buildBatchesView(_T t) {
    if (_loadingBatches && _batches.isEmpty) {
      return Center(child: CircularProgressIndicator(color: DemProColors.accent, strokeWidth: 2));
    }

    if (_batches.isEmpty) {
      return RefreshIndicator(
        color: DemProColors.accent,
        backgroundColor: t.cardBg,
        onRefresh: _loadBatches,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.55,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        color: DemProColors.accent.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.route, color: DemProColors.accent, size: 34),
                    ),
                    const SizedBox(height: 16),
                    Text('Aucune tournée', style: TextStyle(color: t.text, fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                      'Créez une tournée pour regrouper plusieurs livraisons avec un seul livreur.',
                      style: TextStyle(color: t.muted, fontSize: 13, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: () => context.push('/dem-pro/batch/create'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: DemProColors.accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.add, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('Créer une tournée',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                        ]),
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

    final active  = _batches.where((b) {
      final s = b['status'] as String? ?? '';
      return s == 'PENDING' || s == 'ACCEPTED' || s == 'IN_PROGRESS' || s == 'SCHEDULED';
    }).toList();
    final history = _batches.where((b) {
      final s = b['status'] as String? ?? '';
      return s == 'COMPLETED' || s == 'CANCELLED';
    }).toList();

    return RefreshIndicator(
      color: DemProColors.accent,
      backgroundColor: t.cardBg,
      onRefresh: _loadBatches,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        children: [
          if (active.isNotEmpty) ...[
            _SectionLabel(label: 'EN COURS', t: t),
            const SizedBox(height: 10),
            for (final b in active) ...[
              _BatchCard(batch: b, t: t),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
          ],
          if (history.isNotEmpty) ...[
            _SectionLabel(label: 'HISTORIQUE', t: t),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: t.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.border),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < history.length; i++)
                    _BatchHistoryRow(
                      batch: history[i],
                      t: t,
                      isLast: i == history.length - 1,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Filtres ───────────────────────────────────────────────────────────────────

class _FilterTabs extends StatelessWidget {
  final _OrderFilter filter;
  final int totalCount, activeCount, deliveredCount, cancelledCount;
  final ValueChanged<_OrderFilter> onFilterChanged;
  final _T t;
  const _FilterTabs({
    required this.filter, required this.totalCount, required this.activeCount,
    required this.deliveredCount, required this.cancelledCount,
    required this.onFilterChanged, required this.t,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
    child: Row(children: [
      _FilterChip(label: 'Toutes',   count: totalCount,     active: filter == _OrderFilter.all,       onTap: () => onFilterChanged(_OrderFilter.all),       t: t),
      const SizedBox(width: 8),
      _FilterChip(label: 'En cours', count: activeCount,    active: filter == _OrderFilter.active,    onTap: () => onFilterChanged(_OrderFilter.active),    t: t),
      const SizedBox(width: 8),
      _FilterChip(label: 'Livrées',  count: deliveredCount, active: filter == _OrderFilter.delivered, onTap: () => onFilterChanged(_OrderFilter.delivered), t: t),
      const SizedBox(width: 8),
      _FilterChip(label: 'Annulées', count: cancelledCount, active: filter == _OrderFilter.cancelled, onTap: () => onFilterChanged(_OrderFilter.cancelled), t: t),
    ]),
  );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;
  final _T t;
  const _FilterChip({required this.label, required this.count, required this.active, required this.onTap, required this.t});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: active ? DemProColors.accent : t.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? DemProColors.accent : t.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : t.muted,
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        if (count > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: active
                  ? Colors.white.withValues(alpha: 0.25)
                  : DemProColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: active ? Colors.white : DemProColors.accent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ]),
    ),
  );
}

// ── Carte livraison active ────────────────────────────────────────────────────

class _ActiveOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final _T t;
  const _ActiveOrderCard({required this.order, required this.t});

  @override
  Widget build(BuildContext context) {
    final status      = order['status'] as String;
    final pickup      = _shortAddress(order['pickupAddress']   as String? ?? '');
    final delivery    = _shortAddress(order['deliveryAddress'] as String? ?? '');
    final price       = order['price']     as num? ?? 0;
    final createdAt   = order['createdAt'] as String?;
    final driver       = order['driver']       as Map<String, dynamic>?;
    final driverName   = driver?['name']       as String?;
    final hasDriver    = driver != null;
    final batchOrderId = order['batchOrderId'] as String?;
    final statusColor  = _statusColor(status);
    final statusLbl    = _statusLabel(status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: DemProColors.accent.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Livreur + badge statut ──────────────────────────────────────
          Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: hasDriver
                    ? DemProColors.accent.withValues(alpha: 0.15)
                    : t.cardBg2,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: hasDriver
                    ? Text(
                        _driverInitials(driverName),
                        style: const TextStyle(
                          color: DemProColors.accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      )
                    : Icon(Icons.two_wheeler, color: t.muted, size: 18),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasDriver ? (driverName ?? 'Livreur') : 'En attente d\'un livreur…',
                    style: TextStyle(color: t.text, fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  if (hasDriver)
                    Text('Moto · DEM', style: TextStyle(color: t.muted, fontSize: 11)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                statusLbl,
                style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ]),
          const SizedBox(height: 12),

          // ── Adresses ─────────────────────────────────────────────────────
          _AddressRow(icon: Icons.radio_button_on, color: DemProColors.success, label: pickup,   t: t),
          Padding(
            padding: const EdgeInsets.only(left: 7, top: 2, bottom: 2),
            child: Container(width: 1.5, height: 12, color: t.border),
          ),
          _AddressRow(icon: Icons.location_on, color: DemProColors.danger, label: delivery, t: t),
          const SizedBox(height: 12),

          // ── Pied : prix · temps · bouton Suivre ───────────────────────
          Row(children: [
            Icon(Icons.payments_outlined, color: t.muted, size: 14),
            const SizedBox(width: 4),
            Text(_fcfa(price), style: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(width: 14),
            Icon(Icons.schedule_outlined, color: t.muted, size: 14),
            const SizedBox(width: 4),
            Text(_timeAgo(createdAt), style: TextStyle(color: t.muted, fontSize: 12)),
            const Spacer(),
            GestureDetector(
              onTap: () {
                if (batchOrderId != null) {
                  context.push('/dem-pro/batch/tracking', extra: {'batchId': batchOrderId});
                } else {
                  _navigateToOrder(context, order);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: DemProColors.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DemProColors.accent.withValues(alpha: 0.25)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.map_outlined, color: DemProColors.accent, size: 13),
                  SizedBox(width: 4),
                  Text('Suivre', style: TextStyle(color: DemProColors.accent, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final _T t;
  const _AddressRow({required this.icon, required this.color, required this.label, required this.t});

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: color, size: 14),
    const SizedBox(width: 8),
    Expanded(
      child: Text(
        label,
        style: TextStyle(color: t.text, fontSize: 13),
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ]);
}

// ── Ligne historique compacte ─────────────────────────────────────────────────

class _HistoriqueRow extends StatelessWidget {
  final Map<String, dynamic> order;
  final bool isLast;
  final _T t;
  const _HistoriqueRow({required this.order, required this.isLast, required this.t});

  @override
  Widget build(BuildContext context) {
    final status      = order['status'] as String;
    final pickup      = _shortAddress(order['pickupAddress']   as String? ?? '');
    final delivery    = _shortAddress(order['deliveryAddress'] as String? ?? '');
    final price       = order['price'] as num? ?? 0;
    final date        = _formatDateTime(
      order['deliveredAt'] as String? ?? order['createdAt'] as String?,
    );
    final statusColor = _statusColor(status);
    final statusLbl   = _statusLabel(status);
    final radius = isLast
        ? const BorderRadius.vertical(bottom: Radius.circular(16))
        : BorderRadius.zero;

    return InkWell(
      onTap: () => _navigateToOrder(context, order),
      borderRadius: radius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: isLast ? null : Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$pickup → $delivery',
                  style: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(date, style: TextStyle(color: t.muted, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _fcfa(price),
                style: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLbl,
                  style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}

// ── Toggle vue Livraisons / Tournées ─────────────────────────────────────────

class _ViewToggleBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final _T t;
  const _ViewToggleBtn({
    required this.label, required this.icon, required this.active,
    required this.onTap, required this.t,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? DemProColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: active ? Colors.white : t.muted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.white : t.muted,
                fontSize: 13,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Carte tournée active ──────────────────────────────────────────────────────

class _BatchCard extends StatelessWidget {
  final Map<String, dynamic> batch;
  final _T t;
  const _BatchCard({required this.batch, required this.t});

  @override
  Widget build(BuildContext context) {
    final status     = batch['status'] as String? ?? 'PENDING';
    final orders     = (batch['orders'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final total      = (batch['totalPrice'] as num?) ?? 0;
    final pickup     = batch['pickupAddress'] as String? ?? '';
    final driver     = batch['driver'] as Map<String, dynamic>?;
    final createdAt  = batch['createdAt'] as String?;
    final delivered  = orders.where((o) => o['status'] == 'DELIVERED').length;
    final statusColor = _batchStatusColor(status);
    final statusLbl   = _batchStatusLabel(status);
    final isActive    = status == 'ACCEPTED' || status == 'IN_PROGRESS';

    return GestureDetector(
      onTap: () => context.push('/dem-pro/batch/tracking', extra: {'batchId': batch['id'] as String}),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border),
          boxShadow: [
            BoxShadow(
              color: DemProColors.accent.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: DemProColors.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.route, color: DemProColors.accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '${orders.length} arrêt${orders.length > 1 ? 's' : ''}',
                    style: TextStyle(color: t.text, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    driver != null
                        ? 'Livreur : ${driver['name'] as String? ?? 'DEM'}'
                        : 'En recherche de livreur…',
                    style: TextStyle(color: t.muted, fontSize: 11),
                  ),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(statusLbl,
                    style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 12),

            // ── Pickup ───────────────────────────────────────────────────────
            Row(children: [
              const Icon(Icons.radio_button_on, color: DemProColors.accent, size: 13),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pickup.split(',').first.trim(),
                  style: TextStyle(color: t.muted, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            const SizedBox(height: 10),

            // ── Barre de progression ─────────────────────────────────────────
            if (isActive && orders.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: delivered / orders.length,
                  backgroundColor: t.cardBg2,
                  color: DemProColors.success,
                  minHeight: 5,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '$delivered / ${orders.length} livrés',
                style: TextStyle(color: t.muted, fontSize: 11),
              ),
              const SizedBox(height: 10),
            ],

            // ── Pied ─────────────────────────────────────────────────────────
            Row(children: [
              Icon(Icons.payments_outlined, color: t.muted, size: 13),
              const SizedBox(width: 4),
              Text(_fcfa(total), style: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              Icon(Icons.schedule_outlined, color: t.muted, size: 13),
              const SizedBox(width: 4),
              Text(_timeAgo(createdAt), style: TextStyle(color: t.muted, fontSize: 11)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: DemProColors.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DemProColors.accent.withValues(alpha: 0.25)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.map_outlined, color: DemProColors.accent, size: 13),
                  SizedBox(width: 4),
                  Text('Suivi', style: TextStyle(color: DemProColors.accent, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ── Ligne historique tournée ──────────────────────────────────────────────────

class _BatchHistoryRow extends StatelessWidget {
  final Map<String, dynamic> batch;
  final bool isLast;
  final _T t;
  const _BatchHistoryRow({required this.batch, required this.isLast, required this.t});

  @override
  Widget build(BuildContext context) {
    final status      = batch['status'] as String? ?? '';
    final total       = (batch['totalPrice'] as num?) ?? 0;
    final orders      = (batch['orders'] as List?)?.length ?? 0;
    final createdAt   = batch['createdAt'] as String?;
    final statusColor = _batchStatusColor(status);
    final statusLbl   = _batchStatusLabel(status);
    final radius      = isLast
        ? const BorderRadius.vertical(bottom: Radius.circular(16))
        : BorderRadius.zero;

    return InkWell(
      onTap: () => context.push('/dem-pro/batch/tracking', extra: {'batchId': batch['id'] as String}),
      borderRadius: radius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: isLast ? null : Border(bottom: BorderSide(color: t.border)),
        ),
        child: Row(children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '$orders arrêt${orders > 1 ? 's' : ''}',
                style: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(_formatDateTime(createdAt), style: TextStyle(color: t.muted, fontSize: 11)),
            ]),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_fcfa(total), style: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(statusLbl,
                  style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ── État vide intelligent ─────────────────────────────────────────────────────

class _EmptyOrdersState extends StatelessWidget {
  final _T t;
  final bool globallyEmpty;
  final VoidCallback onOrder;
  const _EmptyOrdersState({required this.t, required this.globallyEmpty, required this.onOrder});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: DemProColors.accent.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.two_wheeler, color: DemProColors.accent, size: 40),
          ),
          const SizedBox(height: 20),
          Text(
            globallyEmpty ? 'Aucune livraison encore' : 'Aucune livraison ici',
            style: TextStyle(color: t.text, fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            globallyEmpty
                ? 'Passez votre première commande et suivez-la ici en temps réel'
                : 'Aucune livraison dans cette catégorie pour le moment.',
            style: TextStyle(color: t.muted, fontSize: 13, height: 1.5),
            textAlign: TextAlign.center,
          ),
          if (globallyEmpty) ...[
            const SizedBox(height: 24),
            GestureDetector(
              onTap: onOrder,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: DemProColors.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Commander maintenant',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ]),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Onglet Adresses
// ─────────────────────────────────────────────────────────────────────────────

const _iconMeta = {
  'store':     (Icons.storefront_outlined,     'Boutique'),
  'warehouse': (Icons.warehouse_outlined,       'Entrepôt'),
  'office':    (Icons.business_outlined,        'Bureau'),
  'home':      (Icons.home_outlined,            'Domicile'),
  'other':     (Icons.place_outlined,           'Autre'),
};

class _AdressesTab extends StatefulWidget {
  final _T t;
  const _AdressesTab({required this.t});
  @override
  State<_AdressesTab> createState() => _AdressesTabState();
}

class _AdressesTabState extends State<_AdressesTab> {
  final _repo    = DemProRepository(ApiClient.dio);
  final _search  = TextEditingController();

  List<Map<String, dynamic>> _addresses = [];
  List<Map<String, dynamic>> _recent    = [];
  bool _loading  = true;
  String _query  = '';

  _T get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() => _query = _search.text.toLowerCase()));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([_repo.getAddresses(), _repo.getRecentPickups()]);
      if (!mounted) return;
      setState(() {
        _addresses = results[0];
        _recent    = results[1];
        _loading   = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.isEmpty) return _addresses;
    return _addresses.where((a) {
      final label   = (a['label']   as String? ?? '').toLowerCase();
      final address = (a['address'] as String? ?? '').toLowerCase();
      return label.contains(_query) || address.contains(_query);
    }).toList();
  }

  Future<void> _showForm({Map<String, dynamic>? existing}) async {
    final refreshed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddressFormSheet(t: t, repo: _repo, existing: existing),
    );
    if (refreshed == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> addr) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: t.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Supprimer ?', style: TextStyle(color: t.text, fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          'Voulez-vous supprimer "${addr['label']}" ?',
          style: TextStyle(color: t.muted, fontSize: 13.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Annuler', style: TextStyle(color: t.muted))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: DemProColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.deleteAddress(addr['id'] as String);
      _load();
    } catch (_) {}
  }

  Future<void> _setDefault(Map<String, dynamic> addr) async {
    try {
      await _repo.setDefaultAddress(addr['id'] as String);
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(children: [
        // ── Header ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Mes adresses', style: TextStyle(color: t.text, fontSize: 22, fontWeight: FontWeight.w800)),
                Text('Points de départ favoris', style: TextStyle(color: t.muted, fontSize: 12)),
              ]),
            ),
            IconButton(
              onPressed: () => _showForm(),
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: DemProColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.add, color: DemProColors.accent, size: 22),
              ),
              tooltip: 'Ajouter une adresse',
            ),
          ]),
        ),

        // ── Barre de recherche ────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Container(
            decoration: BoxDecoration(
              color: t.cardBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.border),
            ),
            child: TextField(
              controller: _search,
              style: TextStyle(color: t.text, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Rechercher une adresse…',
                hintStyle: TextStyle(color: t.muted, fontSize: 14),
                prefixIcon: Icon(Icons.search, color: t.muted, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close, color: t.muted, size: 18),
                        onPressed: () { _search.clear(); setState(() => _query = ''); },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),

        // ── Contenu ───────────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: DemProColors.accent, strokeWidth: 2))
              : RefreshIndicator(
                  color: DemProColors.accent,
                  backgroundColor: t.cardBg,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      if (_filtered.isEmpty && _query.isNotEmpty) ...[
                        _buildEmptySearch(),
                      ] else if (_filtered.isEmpty && _recent.isEmpty) ...[
                        _buildEmptyState(),
                      ] else ...[
                        if (_filtered.isNotEmpty) ...[
                          _buildSectionHeader('Favoris', '${_filtered.length}'),
                          const SizedBox(height: 10),
                          ..._filtered.map((a) => _AddressCard(
                            addr: a, t: t,
                            onEdit:       () => _showForm(existing: a),
                            onDelete:     () => _delete(a),
                            onSetDefault: () => _setDefault(a),
                          )),
                          const SizedBox(height: 20),
                        ],
                        if (_recent.isNotEmpty && _query.isEmpty) ...[
                          _buildSectionHeader('Depuis vos commandes', null),
                          const SizedBox(height: 4),
                          Text(
                            'Adresses utilisées récemment comme point de départ',
                            style: TextStyle(color: t.muted, fontSize: 12),
                          ),
                          const SizedBox(height: 10),
                          ..._recent.map((r) => _RecentPickupRow(
                            addr: r, t: t,
                            onSave: () => _showForm(existing: {
                              'address': r['address'],
                              'lat': r['lat'],
                              'lng': r['lng'],
                            }),
                          )),
                        ],
                      ],
                    ],
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _buildSectionHeader(String title, String? count) => Row(children: [
    Text(title, style: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w700)),
    if (count != null) ...[
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: DemProColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(count, style: const TextStyle(color: DemProColors.accent, fontSize: 11, fontWeight: FontWeight.w700)),
      ),
    ],
  ]);

  Widget _buildEmptySearch() => Padding(
    padding: const EdgeInsets.only(top: 60),
    child: Column(children: [
      Icon(Icons.search_off, color: t.muted, size: 40),
      const SizedBox(height: 12),
      Text('Aucun résultat pour "$_query"', style: TextStyle(color: t.text, fontSize: 15, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text('Essayez avec un autre terme.', style: TextStyle(color: t.muted, fontSize: 13)),
    ]),
  );

  Widget _buildEmptyState() => Padding(
    padding: const EdgeInsets.only(top: 60),
    child: Column(children: [
      Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          color: DemProColors.accent.withValues(alpha: 0.08),
          shape: BoxShape.circle,
          border: Border.all(color: DemProColors.accent.withValues(alpha: 0.20), width: 1.5),
        ),
        child: const Icon(Icons.place_outlined, color: DemProColors.accent, size: 32),
      ),
      const SizedBox(height: 16),
      Text('Aucune adresse enregistrée', style: TextStyle(color: t.text, fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(
        'Ajoutez vos points de départ favoris\n(boutique, entrepôt, bureau…)',
        style: TextStyle(color: t.muted, fontSize: 13, height: 1.5),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      GestureDetector(
        onTap: () => _showForm(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(color: DemProColors.accent, borderRadius: BorderRadius.circular(12)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Ajouter une adresse', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
        ),
      ),
    ]),
  );
}

// ── Card adresse favorite ─────────────────────────────────────────────────────

class _AddressCard extends StatelessWidget {
  final Map<String, dynamic> addr;
  final _T t;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;

  const _AddressCard({
    required this.addr, required this.t,
    required this.onEdit, required this.onDelete, required this.onSetDefault,
  });

  @override
  Widget build(BuildContext context) {
    final isDefault = addr['isDefault'] as bool? ?? false;
    final icon      = addr['icon'] as String? ?? 'other';
    final label     = addr['label'] as String? ?? '';
    final address   = addr['address'] as String? ?? '';
    final landmark  = addr['landmark'] as String?;
    final meta      = _iconMeta[icon] ?? _iconMeta['other']!;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDefault ? DemProColors.accent.withValues(alpha: 0.5) : t.border,
          width: isDefault ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: DemProColors.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(meta.$1, color: DemProColors.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(label, style: TextStyle(color: t.text, fontSize: 14, fontWeight: FontWeight.w700)),
                  if (isDefault) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: DemProColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('Par défaut', style: TextStyle(color: DemProColors.accent, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
                const SizedBox(height: 3),
                Text(address, style: TextStyle(color: t.muted, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (landmark != null && landmark.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.info_outline, color: t.muted, size: 12),
                    const SizedBox(width: 4),
                    Expanded(child: Text(landmark, style: TextStyle(color: t.muted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                ],
              ])),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: t.muted, size: 20),
                color: t.cardBg,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (v) {
                  if (v == 'edit')    onEdit();
                  if (v == 'default') onSetDefault();
                  if (v == 'delete')  onDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: _menuItem(Icons.edit_outlined, 'Modifier', t.text)),
                  if (!isDefault)
                    PopupMenuItem(value: 'default', child: _menuItem(Icons.star_outline, 'Définir par défaut', t.text)),
                  PopupMenuItem(value: 'delete', child: _menuItem(Icons.delete_outline, 'Supprimer', DemProColors.danger)),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, Color color) => Row(children: [
    Icon(icon, color: color, size: 18),
    const SizedBox(width: 10),
    Text(label, style: TextStyle(color: color, fontSize: 13.5)),
  ]);
}

// ── Ligne adresse récente (depuis commandes) ──────────────────────────────────

class _RecentPickupRow extends StatelessWidget {
  final Map<String, dynamic> addr;
  final _T t;
  final VoidCallback onSave;

  const _RecentPickupRow({required this.addr, required this.t, required this.onSave});

  @override
  Widget build(BuildContext context) {
    final address = addr['address'] as String? ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: t.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: t.border)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: t.cardBg2, borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.history, color: t.muted, size: 18),
        ),
        title: Text(address, style: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: GestureDetector(
          onTap: onSave,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: DemProColors.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('Sauvegarder', style: TextStyle(color: DemProColors.accent, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

// ── Formulaire adresse (bottom sheet) ────────────────────────────────────────

class _AddressFormSheet extends StatefulWidget {
  final _T t;
  final DemProRepository repo;
  final Map<String, dynamic>? existing;
  const _AddressFormSheet({required this.t, required this.repo, this.existing});
  @override
  State<_AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends State<_AddressFormSheet> {
  final _formKey  = GlobalKey<FormState>();
  late final TextEditingController _label;
  late final TextEditingController _address;
  late final TextEditingController _landmark;
  String _icon      = 'other';
  bool   _isDefault = false;
  bool   _saving    = false;

  bool get _isEdit => widget.existing != null && widget.existing!.containsKey('id');
  _T   get t       => widget.t;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _label    = TextEditingController(text: e?['label']    as String? ?? '');
    _address  = TextEditingController(text: e?['address']  as String? ?? '');
    _landmark = TextEditingController(text: e?['landmark'] as String? ?? '');
    _icon     = e?['icon']      as String? ?? 'other';
    _isDefault = e?['isDefault'] as bool? ?? false;
  }

  @override
  void dispose() {
    _label.dispose(); _address.dispose(); _landmark.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final data = {
        'label':     _label.text.trim(),
        'address':   _address.text.trim(),
        'landmark':  _landmark.text.trim().isEmpty ? null : _landmark.text.trim(),
        'icon':      _icon,
        'isDefault': _isDefault,
      };
      if (_isEdit) {
        await widget.repo.updateAddress(widget.existing!['id'] as String, data);
      } else {
        await widget.repo.createAddress(data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: DemProColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomPadding),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Handle + titre ─────────────────────────────────────────────
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: t.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
            Text(
              _isEdit ? 'Modifier l\'adresse' : 'Nouvelle adresse',
              style: TextStyle(color: t.text, fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),

            // ── Sélecteur d'icône ──────────────────────────────────────────
            Text('Type de lieu', style: TextStyle(color: t.muted, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SizedBox(
              height: 64,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _iconMeta.entries.map((e) {
                  final selected = _icon == e.key;
                  return GestureDetector(
                    onTap: () => setState(() => _icon = e.key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? DemProColors.accent : t.cardBg2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? DemProColors.accent : t.border,
                          width: selected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(e.value.$1, color: selected ? Colors.white : t.muted, size: 20),
                        const SizedBox(height: 3),
                        Text(e.value.$2, style: TextStyle(color: selected ? Colors.white : t.muted, fontSize: 10, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // ── Libellé ────────────────────────────────────────────────────
            _FieldLabel('Libellé', t),
            const SizedBox(height: 6),
            _FormField(
              controller: _label, t: t,
              hint: 'ex: Boutique Médina, Entrepôt Pikine…',
              validator: (v) => (v == null || v.trim().length < 2) ? 'Minimum 2 caractères' : null,
            ),
            const SizedBox(height: 14),

            // ── Adresse ────────────────────────────────────────────────────
            _FieldLabel('Adresse', t),
            const SizedBox(height: 6),
            _FormField(
              controller: _address, t: t,
              hint: 'ex: Rue 10 x Gueule Tapée, Médina, Dakar',
              validator: (v) => (v == null || v.trim().length < 4) ? 'Adresse trop courte' : null,
            ),
            const SizedBox(height: 14),

            // ── Repère ─────────────────────────────────────────────────────
            _FieldLabel('Repère (optionnel)', t),
            const SizedBox(height: 6),
            _FormField(
              controller: _landmark, t: t,
              hint: 'ex: Face à la mosquée, derrière la station Total…',
              validator: null,
            ),
            const SizedBox(height: 16),

            // ── Adresse par défaut ─────────────────────────────────────────
            Container(
              decoration: BoxDecoration(color: t.cardBg2, borderRadius: BorderRadius.circular(12), border: Border.all(color: t.border)),
              child: SwitchListTile(
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v),
                activeTrackColor: DemProColors.accent,
                activeThumbColor: Colors.white,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: t.border,
                title: Text('Adresse par défaut', style: TextStyle(color: t.text, fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text('Pré-sélectionnée lors d\'une nouvelle commande', style: TextStyle(color: t.muted, fontSize: 12)),
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              ),
            ),
            const SizedBox(height: 24),

            // ── CTA ────────────────────────────────────────────────────────
            SizedBox(
              width: double.infinity, height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: DemProColors.accent,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: DemProColors.accent.withValues(alpha: 0.30), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _saving ? null : _submit,
                    child: Center(
                      child: _saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(
                              _isEdit ? 'Enregistrer les modifications' : 'Ajouter l\'adresse',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final _T t;
  const _FieldLabel(this.text, this.t);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(color: t.muted, fontSize: 12, fontWeight: FontWeight.w600));
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final _T t;
  final String hint;
  final String? Function(String?)? validator;
  const _FormField({required this.controller, required this.t, required this.hint, required this.validator});

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    validator: validator,
    style: TextStyle(color: t.text, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: t.muted, fontSize: 13),
      filled: true,
      fillColor: t.cardBg2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.accent, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.danger)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.danger, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Onglet Finances
// ─────────────────────────────────────────────────────────────────────────────

const _periodOptions = [
  ('today',      'Jour'),
  ('this_week',  'Semaine'),
  ('this_month', 'Mois'),
  ('3months',    '3 mois'),
];

enum _FinanceView { sales, deliveries }

class _FinancesTab extends StatefulWidget {
  final _T t;
  const _FinancesTab({required this.t});
  @override
  State<_FinancesTab> createState() => _FinancesTabState();
}

class _FinancesTabState extends State<_FinancesTab> {
  final _repo    = DemProRepository(ApiClient.dio);
  final _ordRepo = OrdersRepository();

  String _period = 'this_month';
  _FinanceView _view = _FinanceView.sales;

  Map<String, dynamic>? _financeData;
  List<Map<String, dynamic>> _orders = [];
  bool   _loading = true;
  String? _error;

  _T get t => widget.t;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _repo.getMyFinances(_period),
        _repo.getMyOrders(),
      ]);
      if (!mounted) return;
      setState(() {
        _financeData = results[0] as Map<String, dynamic>;
        _orders = (results[1] as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _selectPeriod(String p) {
    if (p == _period) return;
    setState(() => _period = p);
    _load();
  }

  // ── Filtrage des commandes par période ────────────────────────────────────
  List<Map<String, dynamic>> get _filteredOrders {
    final now = DateTime.now();
    final delivered = _orders.where((o) {
      final s = (o['status'] as String? ?? '').toUpperCase();
      return s == 'DELIVERED' || s == 'PAYMENT_CONFIRMED';
    }).where((o) {
      final dt = DateTime.tryParse(o['createdAt'] as String? ?? '')?.toLocal();
      if (dt == null) return false;
      return switch (_period) {
        'today'      => dt.year == now.year && dt.month == now.month && dt.day == now.day,
        'this_week'  => now.difference(dt).inDays < 7,
        'this_month' => dt.year == now.year && dt.month == now.month,
        '3months'    => now.difference(dt).inDays < 90,
        _            => true,
      };
    }).toList();
    delivered.sort((a, b) => (b['createdAt'] as String? ?? '').compareTo(a['createdAt'] as String? ?? ''));
    return delivered;
  }

  int get _totalSales {
    int total = 0;
    for (final o in _filteredOrders) {
      final items = o['items'] as List?;
      if (items != null) {
        for (final item in items) {
          total += ((item['price'] as num?)?.toInt() ?? 0) * ((item['quantity'] as num?)?.toInt() ?? 1);
        }
      }
    }
    return total;
  }

  int get _totalDelivery {
    int total = 0;
    for (final o in _filteredOrders) {
      total += (o['price'] as num?)?.toInt() ?? 0;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(children: [

        // ── Header ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(children: [
            Expanded(child: Text('Finances', style: TextStyle(color: t.text, fontSize: 22, fontWeight: FontWeight.w800))),
          ]),
        ),

        // ── Filtre 1 — Période ───────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Row(children: _periodOptions.map((opt) {
            final selected = _period == opt.$1;
            return Expanded(child: GestureDetector(
              onTap: () => _selectPeriod(opt.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: EdgeInsets.only(right: opt.$1 != '3months' ? 6 : 0),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: selected ? DemProColors.accent : t.cardBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: selected ? DemProColors.accent : t.border),
                ),
                child: Text(
                  opt.$2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? Colors.white : t.muted,
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ));
          }).toList()),
        ),

        // ── Filtre 2 — Ventes / Livraisons ──────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: t.cardBg2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              _FinanceToggle(
                label: 'Ventes',
                icon: Icons.shopping_bag_outlined,
                active: _view == _FinanceView.sales,
                onTap: () => setState(() => _view = _FinanceView.sales),
                t: t,
              ),
              _FinanceToggle(
                label: 'Livraisons',
                icon: Icons.two_wheeler,
                active: _view == _FinanceView.deliveries,
                onTap: () => setState(() => _view = _FinanceView.deliveries),
                t: t,
              ),
            ]),
          ),
        ),

        // ── Contenu ───────────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: DemProColors.accent, strokeWidth: 2))
              : _error != null
                  ? _buildError()
                  : RefreshIndicator(
                      color: DemProColors.accent,
                      backgroundColor: t.cardBg,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: _view == _FinanceView.sales
                            ? _buildSalesContent()
                            : _buildDeliveriesContent(),
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _buildError() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.wifi_off_rounded, color: t.muted, size: 36),
    const SizedBox(height: 12),
    Text('Impossible de charger les données', style: TextStyle(color: t.text, fontSize: 15, fontWeight: FontWeight.w600)),
    const SizedBox(height: 16),
    GestureDetector(
      onTap: _load,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(color: DemProColors.accent, borderRadius: BorderRadius.circular(10)),
        child: const Text('Réessayer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
      ),
    ),
  ]));

  // ── Vue VENTES ──────────────────────────────────────────────────────────────

  List<Widget> _buildSalesContent() {
    final orders = _filteredOrders;
    int totalItems = 0;
    for (final o in orders) {
      final items = o['items'] as List?;
      if (items != null) totalItems += items.length;
    }

    return [
      // Résumé ventes
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: t.dark
                ? [DemProColors.bg3, DemProColors.bg4]
                : [const Color(0xFFEFF6FF), const Color(0xFFDCEFFB)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: DemProColors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.trending_up, color: DemProColors.success, size: 16),
            ),
            const SizedBox(width: 8),
            Text('Ventes', style: TextStyle(color: t.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 14),
          Text(
            '${_fcfa(_totalSales)} FCFA',
            style: TextStyle(color: t.text, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5),
          ),
          Text('Chiffre d\'affaires', style: TextStyle(color: t.muted, fontSize: 12)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _MiniStat(
              value: orders.length.toString(),
              label: 'Commandes',
              color: DemProColors.accent,
              t: t,
            )),
            Container(width: 1, height: 40, color: t.border),
            Expanded(child: _MiniStat(
              value: totalItems.toString(),
              label: 'Articles vendus',
              color: DemProColors.success,
              t: t,
            )),
          ]),
        ]),
      ),
      const SizedBox(height: 20),

      // Historique ventes
      Row(children: [
        Text('Historique des ventes', style: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: DemProColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('${orders.length}', style: const TextStyle(color: DemProColors.accent, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ]),
      const SizedBox(height: 10),
      if (orders.isEmpty)
        _buildEmpty('Aucune vente sur cette période')
      else
        ...orders.map((o) => _SaleRow(order: o, t: t)),
    ];
  }

  // ── Vue LIVRAISONS ─────────────────────────────────────────────────────────

  List<Widget> _buildDeliveriesContent() {
    final orders  = _filteredOrders;
    final summary = _financeData?['summary'] as Map<String, dynamic>? ?? {};
    final total   = (summary['totalSpent']         as num?) ?? _totalDelivery;
    final count   = (summary['deliveriesCount']    as num?) ?? orders.length;
    final avg     = (summary['avgCostPerDelivery'] as num?) ?? (orders.isNotEmpty ? _totalDelivery / orders.length : 0);
    final breakdown = (_financeData?['breakdown'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return [
      // Résumé livraisons
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: t.dark
                ? [DemProColors.bg3, DemProColors.bg4]
                : [const Color(0xFFEFF6FF), const Color(0xFFDCEFFB)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: DemProColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.two_wheeler, color: DemProColors.accent, size: 16),
            ),
            const SizedBox(width: 8),
            Text('Livraisons', style: TextStyle(color: t.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 14),
          Text(
            '${_fcfa(total.toInt())} FCFA',
            style: TextStyle(color: t.text, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5),
          ),
          Text('Total dépensé', style: TextStyle(color: t.muted, fontSize: 12)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _MiniStat(
              value: count.toInt().toString(),
              label: 'Livraisons',
              color: DemProColors.accent,
              t: t,
            )),
            Container(width: 1, height: 40, color: t.border),
            Expanded(child: _MiniStat(
              value: '${_fcfa(avg.toInt())}',
              label: 'Coût moyen',
              color: DemProColors.success,
              t: t,
            )),
          ]),
        ]),
      ),
      const SizedBox(height: 16),

      // Graphique
      if (breakdown.isNotEmpty) ...[
        _buildChart(breakdown),
        const SizedBox(height: 20),
      ],

      // Transactions
      Row(children: [
        Text('Transactions', style: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: DemProColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('${orders.length}', style: const TextStyle(color: DemProColors.accent, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ]),
      const SizedBox(height: 10),
      if (orders.isEmpty)
        _buildEmpty('Aucune livraison sur cette période')
      else
        ...orders.map((o) => _DeliveryRow(order: o, t: t)),
    ];
  }

  Widget _buildChart(List<Map<String, dynamic>> breakdown) {
    final maxAmt = breakdown
        .map((b) => (b['amount'] as num?)?.toDouble() ?? 0.0)
        .fold(0.0, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Évolution', style: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: breakdown.asMap().entries.map((entry) {
              final b      = entry.value;
              final amount = (b['amount'] as num?)?.toDouble() ?? 0.0;
              final label  = b['label'] as String? ?? '';
              final count  = (b['count'] as num?)?.toInt() ?? 0;
              final ratio  = maxAmt > 0 ? amount / maxAmt : 0.0;
              final barH   = ratio == 0 ? 4.0 : 8.0 + ratio * 72.0;
              final isLast = entry.key == breakdown.length - 1;

              return Expanded(child: Padding(
                padding: EdgeInsets.only(right: isLast ? 0 : 6),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (count > 0) ...[
                    Text(_fcfa(amount.toInt()),
                      style: TextStyle(color: DemProColors.accent, fontSize: 9, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                  ] else
                    const SizedBox(height: 18),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                    height: barH,
                    decoration: BoxDecoration(
                      color: count > 0
                          ? DemProColors.accent.withValues(alpha: 0.25 + 0.75 * ratio)
                          : t.border,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(label,
                    style: TextStyle(color: t.muted, fontSize: 8.5, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center, maxLines: 2),
                ]),
              ));
            }).toList(),
          ),
        ),
      ]),
    );
  }

  Widget _buildEmpty(String msg) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: t.cardBg,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: t.border),
    ),
    child: Column(children: [
      Icon(Icons.receipt_long_outlined, color: t.muted, size: 36),
      const SizedBox(height: 10),
      Text(msg, style: TextStyle(color: t.text, fontSize: 14, fontWeight: FontWeight.w600)),
    ]),
  );
}

// ── Toggle Ventes / Livraisons ──────────────────────────────────────────────

class _FinanceToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final _T t;
  const _FinanceToggle({required this.label, required this.icon, required this.active, required this.onTap, required this.t});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: active ? DemProColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 14, color: active ? Colors.white : t.muted),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
            color: active ? Colors.white : t.muted,
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          )),
        ]),
      ),
    ),
  );
}

// ── Mini-stat dans la card résumé ────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  final Color  color;
  final _T     t;
  const _MiniStat({required this.value, required this.label, required this.color, required this.t});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(color: t.muted, fontSize: 11.5)),
    ]),
  );
}

// ── Ligne vente (avec articles) ─────────────────────────────────────────────

class _SaleRow extends StatelessWidget {
  final Map<String, dynamic> order;
  final _T t;
  const _SaleRow({required this.order, required this.t});

  @override
  Widget build(BuildContext context) {
    final items     = (order['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final desc      = order['description'] as String? ?? '';
    final date      = _formatDateTime(order['createdAt'] as String?);
    final receiver  = order['receiverName'] as String?;
    final address   = _shortAddress(order['deliveryAddress'] as String? ?? '');
    final payMode   = order['paymentMode'] as String?;

    int saleTotal = 0;
    for (final item in items) {
      saleTotal += ((item['price'] as num?)?.toInt() ?? 0) * ((item['quantity'] as num?)?.toInt() ?? 1);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: DemProColors.success.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.shopping_bag_outlined, color: DemProColors.success, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(receiver ?? address, style: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(date, style: TextStyle(color: t.muted, fontSize: 11)),
          ])),
          if (saleTotal > 0)
            Text('${_fcfa(saleTotal)} F', style: const TextStyle(color: DemProColors.success, fontSize: 14, fontWeight: FontWeight.w800)),
        ]),

        // Articles
        if (items.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: t.cardBg2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(children: items.map((item) {
              final name = item['name'] as String? ?? '—';
              final qty  = (item['quantity'] as num?)?.toInt() ?? 1;
              final price = (item['price'] as num?)?.toInt();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Text('$name', style: TextStyle(color: t.text, fontSize: 12)),
                  Text('  × $qty', style: TextStyle(color: t.muted, fontSize: 12)),
                  const Spacer(),
                  if (price != null)
                    Text('${_fcfa(price * qty)} F', style: TextStyle(color: t.text, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              );
            }).toList()),
          ),
        ] else if (desc.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(desc, style: TextStyle(color: t.muted, fontSize: 11.5), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],

        // Paiement
        if (payMode != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(
              payMode == 'merchant' ? Icons.storefront_outlined : Icons.payments_outlined,
              color: t.muted, size: 13,
            ),
            const SizedBox(width: 4),
            Text(
              payMode == 'merchant' ? 'Payé par vous' : 'Payé à la livraison',
              style: TextStyle(color: t.muted, fontSize: 11),
            ),
          ]),
        ],
      ]),
    );
  }
}

// ── Ligne livraison ─────────────────────────────────────────────────────────

class _DeliveryRow extends StatelessWidget {
  final Map<String, dynamic> order;
  final _T t;
  const _DeliveryRow({required this.order, required this.t});

  @override
  Widget build(BuildContext context) {
    final address    = _shortAddress(order['deliveryAddress'] as String? ?? '—');
    final amount     = (order['price'] as num?)?.toInt() ?? 0;
    final driver     = order['driver'] as Map<String, dynamic>?;
    final driverName = driver?['name'] as String?;
    final date       = _formatDateTime(order['createdAt'] as String?);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: DemProColors.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.two_wheeler, color: DemProColors.accent, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(address, style: TextStyle(color: t.text, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Row(children: [
            Text(date, style: TextStyle(color: t.muted, fontSize: 11)),
            if (driverName != null && driverName.isNotEmpty) ...[
              Text('  ·  ', style: TextStyle(color: t.muted, fontSize: 11)),
              Expanded(child: Text(driverName, style: TextStyle(color: t.muted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ]),
        ])),
        const SizedBox(width: 12),
        Text('${_fcfa(amount)} F', style: const TextStyle(color: DemProColors.accent, fontSize: 13.5, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}
