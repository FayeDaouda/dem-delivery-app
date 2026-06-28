import 'package:dio/dio.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/router/app_startup_notifier.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/api_client.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/profile/data/profile_repository.dart';
import '../data/chef_de_flotte_repository.dart';
import '../../../core/utils/dem_layout.dart';

class ChefDeFlotteProfileScreen extends StatefulWidget {
  const ChefDeFlotteProfileScreen({super.key});
  @override
  State<ChefDeFlotteProfileScreen> createState() => _State();
}

class _State extends State<ChefDeFlotteProfileScreen> {
  final _profileRepo = ProfileRepository();
  final _amRepo      = ChefDeFlotteRepository(ApiClient.dio);
  final _picker      = ImagePicker();

  Map<String, dynamic>?       _user;
  Map<String, dynamic>?       _stats;
  List<Map<String, dynamic>>  _drivers = [];
  bool _loading         = true;
  bool _uploadingAvatar = false;
  final Set<String> _expandedDrivers = {};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _profileRepo.getMe(),
        _amRepo.getStats(),
        _amRepo.getDrivers(),
      ]);
      if (mounted) {
        setState(() {
          _user    = results[0] as Map<String, dynamic>;
          _stats   = results[1] as Map<String, dynamic>;
          _drivers = results[2] as List<Map<String, dynamic>>;
          _loading = false;
        });
      }
    } catch (_) {
      final cached = await AuthStorage.getUser();
      if (mounted) { setState(() { _user = cached; _loading = false; }); }
    }
  }

  // ── Avatar upload ──────────────────────────────────────────────────────────

  Future<void> _pickAvatar() async {
    final src = await _showPickerSource();
    if (src == null) return;
    try {
      final file = await _picker.pickImage(source: src, imageQuality: 85);
      if (file == null) return;
      setState(() => _uploadingAvatar = true);
      final formData = FormData.fromMap({
        'file':  await MultipartFile.fromFile(file.path, filename: file.name),
        'field': 'avatar',
      });
      final res = await ApiClient.dio.post('/users/driver/documents', data: formData);
      final url = res.data['user']?['avatar'] as String?;
      if (url != null && mounted) { setState(() => _user?['avatar'] = url); }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de l\'envoi de la photo.')));
      }
    } finally {
      if (mounted) { setState(() => _uploadingAvatar = false); }
    }
  }

  Future<ImageSource?> _showPickerSource() => showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Photo de profil', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _PickOption(icon: Icons.camera_alt_outlined, label: 'Caméra',  color: AppColors.primary,    onTap: () => Navigator.pop(context, ImageSource.camera))),
            const SizedBox(width: 12),
            Expanded(child: _PickOption(icon: Icons.photo_library_outlined, label: 'Galerie', color: AppColors.primaryMid, onTap: () => Navigator.pop(context, ImageSource.gallery))),
          ]),
        ]),
      ),
    ),
  );

  // ── Support ────────────────────────────────────────────────────────────────

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d\'ouvrir la page')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d\'ouvrir la page')),
        );
      }
    }
  }

  void _showSupport() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(gradient: AppColors.gradientSplash, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Icon(Icons.support_agent_outlined, color: Colors.white, size: 40),
          const SizedBox(height: 8),
          const Text('Support DEM', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          _SupportTile(icon: Icons.phone_outlined,      label: 'Appeler le support', sub: '+221 71 006 46 64', onTap: () => _launch('tel:+221710064664')),
          const SizedBox(height: 10),
          _SupportTile(icon: Icons.email_outlined,      label: 'Envoyer un e-mail',  sub: 'support@dem.sn',   onTap: () => _launch('mailto:support@dem.sn')),
          const SizedBox(height: 10),
          _SupportTile(icon: Icons.chat_bubble_outline, label: 'WhatsApp',           sub: '+221 71 006 46 64', onTap: () => _launch('https://wa.me/221710064664')),
        ]),
      ),
    );
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  Future<void> _logout() async {
    final ok = await _confirm(title: 'Déconnexion', message: 'Vous allez être déconnecté.', actionLabel: 'Déconnexion', danger: false);
    if (ok != true) return;
    await AuthStorage.clear();
    appStartupNotifier.markLoggedOut();
    if (mounted) { context.go('/phone'); }
  }

  Future<void> _deleteAccount() async {
    final ok = await _confirm(title: 'Supprimer le compte', message: 'Cette action est irréversible. Toutes vos données seront supprimées.', actionLabel: 'Supprimer', danger: true);
    if (ok != true) return;
    try {
      await ApiClient.dio.delete('/users/me');
      await AuthStorage.clear();
      appStartupNotifier.markLoggedOut();
    if (mounted) { context.go('/phone'); }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red));
      }
    }
  }

  Future<bool?> _confirm({required String title, required String message, required String actionLabel, required bool danger}) =>
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF0F2942))),
        content: Text(message, style: const TextStyle(color: Color(0xFF6B7280), height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler', style: TextStyle(color: AppColors.primaryMid))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(actionLabel, style: TextStyle(color: danger ? Colors.red : AppColors.primaryMid, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: Colors.white, body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    }

    final name         = _user?['name']            as String? ?? '—';
    final phone        = _user?['phone']           as String? ?? '—';
    final status       = _user?['chefDeFlotteStatus'] as String? ?? 'PENDING';
    final avatarUrl    = _user?['avatar']          as String?;
    final companyName  = _user?['companyName']     as String?;
    final ninea        = _user?['ninea']            as String?;
    final rccm         = _user?['rccm']             as String?;
    final cniRecto     = _user?['cniRecto']        as String?;
    final cniVerso     = _user?['cniVerso']        as String?;
    final fleetSize    = (_stats?['fleetSize']     as num?)?.toInt() ?? 0;
    final fleetMax     = (_stats?['fleetMax']      as num?)?.toInt() ?? 10;
    final activeCount  = (_stats?['activeCount']   as num?)?.toInt() ?? 0;
    final pendingCount = (_stats?['pendingCount']  as num?)?.toInt() ?? 0;
    final totalCourses = (_stats?['totalCourses']  as num?)?.toInt() ?? 0;

    final initials = name.trim().isNotEmpty
        ? name.trim().split(' ').take(2).map((w) => w[0].toUpperCase()).join()
        : '?';
    final isTablet = DemLayout.isTablet(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [

          // ── Header ──────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: isTablet ? 280.0 : 230.0,
            pinned: true,
            backgroundColor: AppColors.primaryDark,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              IconButton(icon: const Icon(Icons.refresh, size: 20), tooltip: 'Actualiser', onPressed: _load),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Avatar cliquable
                      GestureDetector(
                        onTap: _uploadingAvatar ? null : _pickAvatar,
                        child: Stack(
                          children: [
                            Container(
                              width: 76, height: 76,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.20),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.50), width: 2),
                              ),
                              child: _uploadingAvatar
                                  ? const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
                                  : avatarUrl != null
                                      ? ClipOval(child: Image.network(avatarUrl, fit: BoxFit.cover, width: 76, height: 76,
                                          errorBuilder: (ctx, err, _) => Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)))))
                                      : Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800))),
                            ),
                            Positioned(
                              bottom: 0, right: 0,
                              child: Container(
                                width: 24, height: 24,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.primaryMid, width: 1.5),
                                ),
                                child: const Icon(Icons.camera_alt, size: 12, color: AppColors.primaryMid),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(phone, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13)),
                      const SizedBox(height: 10),
                      _StatusBadge(status: status),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // Stats
                Row(children: [
                  _MiniStat(label: 'Flotte active', value: '$activeCount', icon: Icons.check_circle_outline, color: Colors.green),
                  const SizedBox(width: 10),
                  _MiniStat(label: 'En attente', value: '$pendingCount', icon: Icons.hourglass_top_rounded, color: Colors.orange),
                  const SizedBox(width: 10),
                  _MiniStat(label: 'Courses', value: '$totalCourses', icon: Icons.motorcycle, color: AppColors.primaryMid),
                ]),
                const SizedBox(height: 12),

                // Barre flotte
                _InfoCard(children: [
                  Row(children: [
                    const Icon(Icons.directions_bike, color: AppColors.primaryMid, size: 18),
                    const SizedBox(width: 8),
                    Text('Flotte : $fleetSize / $fleetMax', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0F2942))),
                    const Spacer(),
                    Text('$fleetSize/$fleetMax', style: TextStyle(color: AppColors.primaryMid.withValues(alpha: 0.70), fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fleetMax > 0 ? fleetSize / fleetMax : 0,
                      minHeight: 6,
                      backgroundColor: const Color(0xFFE5E7EB),
                      valueColor: AlwaysStoppedAnimation<Color>(fleetSize >= fleetMax ? Colors.orange : AppColors.primary),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),

                // Infos personnelles
                _SectionHeader(title: 'Informations personnelles', icon: Icons.person_outline),
                const SizedBox(height: 10),
                _InfoCard(children: [
                  _InfoRow(icon: Icons.person_outline, label: 'Nom',       value: name),
                  const Divider(height: 16),
                  _InfoRow(icon: Icons.phone_outlined,  label: 'Téléphone', value: phone),
                ]),
                const SizedBox(height: 20),

                // Entreprise
                if (companyName != null || ninea != null || rccm != null) ...[
                  _SectionHeader(title: 'Entreprise', icon: Icons.business_outlined),
                  const SizedBox(height: 10),
                  _InfoCard(children: [
                    if (companyName != null) _InfoRow(icon: Icons.store_outlined,   label: 'Nom',   value: companyName),
                    if (companyName != null && (ninea != null || rccm != null)) const Divider(height: 16),
                    if (ninea != null) _InfoRow(icon: Icons.tag,                    label: 'NINEA', value: ninea),
                    if (ninea != null && rccm != null) const Divider(height: 16),
                    if (rccm  != null) _InfoRow(icon: Icons.article_outlined,       label: 'RCCM',  value: rccm),
                  ]),
                  const SizedBox(height: 20),
                ],

                // Documents AM
                _SectionHeader(title: 'Documents', icon: Icons.badge_outlined),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _DocThumb(url: cniRecto, label: 'CNI recto')),
                  const SizedBox(width: 12),
                  Expanded(child: _DocThumb(url: cniVerso, label: 'CNI verso')),
                ]),
                const SizedBox(height: 24),

                // ── Mes livreurs ─────────────────────────────────────────
                _SectionHeader(title: 'Mes livreurs (${_drivers.length})', icon: Icons.group_outlined),
                const SizedBox(height: 10),
                if (_drivers.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE5E7EB))),
                    child: const Center(child: Text('Aucun livreur dans votre flotte.', style: TextStyle(color: Colors.grey, fontSize: 13))),
                  )
                else
                  ...(_drivers.map((d) => _DriverCard(
                    driver: d,
                    expanded: _expandedDrivers.contains(d['id'] as String? ?? ''),
                    onToggle: () => setState(() {
                      final id = d['id'] as String? ?? '';
                      if (_expandedDrivers.contains(id)) { _expandedDrivers.remove(id); }
                      else { _expandedDrivers.add(id); }
                    }),
                  ))),
                const SizedBox(height: 24),

                // ── Support DEM ───────────────────────────────────────────
                _SectionHeader(title: 'Contacter DEM', icon: Icons.support_agent_outlined),
                const SizedBox(height: 10),
                _ActionTile(
                  icon: Icons.support_agent_outlined,
                  label: 'Service client DEM',
                  color: AppColors.primaryMid,
                  onTap: _showSupport,
                ),
                const SizedBox(height: 24),

                // Compte
                _SectionHeader(title: 'Compte', icon: Icons.settings_outlined),
                const SizedBox(height: 10),
                _ActionTile(icon: Icons.logout, label: 'Déconnexion', color: AppColors.primaryMid, onTap: _logout),
                const SizedBox(height: 8),
                _ActionTile(icon: Icons.delete_outline, label: 'Supprimer mon compte', color: Colors.red, onTap: _deleteAccount),

              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Driver card (flotte) ──────────────────────────────────────────────────────

class _DriverCard extends StatelessWidget {
  final Map<String, dynamic> driver;
  final bool expanded;
  final VoidCallback onToggle;
  const _DriverCard({required this.driver, required this.expanded, required this.onToggle});

  Color get _statusColor {
    final s = driver['chefDeFlotteStatus'] as String? ?? '';
    final active = driver['isActive'] as bool? ?? false;
    if (s == 'ACTIVE' && active)  return Colors.green;
    if (s == 'ACTIVE' && !active) return Colors.grey;
    if (s == 'PENDING')           return Colors.orange;
    if (s == 'REJECTED')          return Colors.red;
    return Colors.grey;
  }

  String get _statusLabel {
    final s = driver['chefDeFlotteStatus'] as String? ?? '';
    final active = driver['isActive'] as bool? ?? false;
    if (s == 'ACTIVE' && active)  return 'Actif';
    if (s == 'ACTIVE' && !active) return 'Suspendu';
    if (s == 'PENDING')           return 'En attente';
    if (s == 'REJECTED')          return 'Refusé';
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final courses = (driver['deliveredCourses'] as num?)?.toInt() ?? 0;
    final rating  = (driver['avgRating'] as num?)?.toDouble();
    final docs = [
      (driver['licenseFront']  as String?, 'Permis recto'),
      (driver['licenseBack']   as String?, 'Permis verso'),
      (driver['vehiclePhoto']  as String?, 'Véhicule'),
      (driver['casquePhoto']   as String?, 'Casque'),
      (driver['cniRecto']      as String?, 'CNI recto'),
      (driver['cniVerso']      as String?, 'CNI verso'),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
      ),
      child: Column(children: [
        // Ligne résumé
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              CircleAvatar(
                backgroundColor: AppColors.primaryMid.withValues(alpha: 0.12),
                child: Text((driver['name'] ?? '?').toString()[0].toUpperCase(),
                    style: const TextStyle(color: AppColors.primaryMid, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(driver['name'] ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Text(driver['phone'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
              const SizedBox(width: 8),
              Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: Colors.grey.shade400, size: 20),
            ]),
          ),
        ),

        // Documents dépliables
        if (expanded) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Documents', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey, letterSpacing: 0.5)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: docs.map((d) => _DocMini(url: d.$1, label: d.$2)).toList(),
              ),
              if (driver['isVerified'] == true) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.verified_outlined, size: 13, color: Colors.green.shade600),
                  const SizedBox(width: 4),
                  Text('Dossier vérifié', style: TextStyle(fontSize: 11, color: Colors.green.shade600, fontWeight: FontWeight.w600)),
                ]),
              ],
            ]),
          ),
        ],
      ]),
    );
  }
}

// ── Doc mini thumbnail ────────────────────────────────────────────────────────

class _DocMini extends StatefulWidget {
  final String? url;
  final String  label;
  const _DocMini({required this.url, required this.label});
  @override
  State<_DocMini> createState() => _DocMiniState();
}

class _DocMiniState extends State<_DocMini> {
  bool _zoomed = false;
  @override
  Widget build(BuildContext context) {
    if (widget.url == null) {
      return Container(
        width: 72, height: 60,
        decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE5E7EB))),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.image_not_supported_outlined, color: Colors.grey, size: 18),
          const SizedBox(height: 2),
          Text(widget.label, style: const TextStyle(fontSize: 8, color: Colors.grey), textAlign: TextAlign.center),
        ]),
      );
    }
    return GestureDetector(
      onTap: () => setState(() => _zoomed = true),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(widget.url!, width: 72, height: 60, fit: BoxFit.cover,
                errorBuilder: (ctx, err, _) => Container(width: 72, height: 60, color: const Color(0xFFF1F5F9), child: const Icon(Icons.broken_image_outlined, color: Colors.grey, size: 20))),
          ),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8))),
              child: Text(widget.label, style: const TextStyle(color: Colors.white, fontSize: 8), textAlign: TextAlign.center),
            ),
          ),
          if (_zoomed)
            GestureDetector(
              onTap: () => setState(() => _zoomed = false),
              child: Positioned.fill(
                child: Container(color: Colors.transparent),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Support tile ──────────────────────────────────────────────────────────────

class _SupportTile extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final VoidCallback onTap;
  const _SupportTile({required this.icon, required this.label, required this.sub, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: 0.15),
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            Text(sub, style: TextStyle(color: Colors.white.withValues(alpha: 0.70), fontSize: 12)),
          ]),
          const Spacer(),
          Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.50), size: 20),
        ]),
      ),
    ),
  );
}

// ── Pick option (camera / gallery) ────────────────────────────────────────────

class _PickOption extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _PickOption({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.20))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ]),
    ),
  );
}

// ── Widgets communs ───────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    final map = {
      'ACTIVE':   (Colors.green, Icons.check_circle,           'Compte actif'),
      'PENDING':  (Colors.orange, Icons.hourglass_top_rounded, 'En attente de validation'),
      'REJECTED': (Colors.red,   Icons.cancel_outlined,        'Dossier refusé'),
    };
    final s = map[status] ?? (Colors.grey, Icons.help_outline, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: s.$1.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20), border: Border.all(color: s.$1.withValues(alpha: 0.50))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(s.$2, size: 14, color: Colors.white),
        const SizedBox(width: 6),
        Text(s.$3, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value; final IconData icon; final Color color;
  const _MiniStat({required this.label, required this.value, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)], border: Border.all(color: const Color(0xFFE5E7EB))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
      ]),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final String title; final IconData icon;
  const _SectionHeader({required this.title, required this.icon});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: AppColors.primaryMid, size: 16),
    const SizedBox(width: 7),
    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.primaryMid)),
  ]);
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE5E7EB)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon; final String label, value;
  const _InfoRow({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: const Color(0xFF9CA3AF), size: 16),
    const SizedBox(width: 10),
    Text('$label  ', style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
    Expanded(child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1F2937)), overflow: TextOverflow.ellipsis)),
  ]);
}

class _DocThumb extends StatelessWidget {
  final String? url; final String label;
  const _DocThumb({required this.url, required this.label});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: url != null
            ? Image.network(url!, height: 100, width: double.infinity, fit: BoxFit.cover,
                errorBuilder: (ctx, err, _) => _placeholder())
            : _placeholder(),
      ),
    ],
  );
  Widget _placeholder() => Container(
    height: 100, width: double.infinity,
    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5)),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade400, size: 28),
      const SizedBox(height: 4),
      Text('Non fourni', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
    ]),
  );
}

class _ActionTile extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _ActionTile({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE5E7EB))),
        child: Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 18)),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: color)),
          const Spacer(),
          Icon(Icons.chevron_right, color: Colors.grey.shade300, size: 20),
        ]),
      ),
    ),
  );
}
