import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/profile/data/profile_repository.dart';
import '../data/ambassador_repository.dart';

class AmbassadorProfileScreen extends StatefulWidget {
  const AmbassadorProfileScreen({super.key});
  @override
  State<AmbassadorProfileScreen> createState() => _State();
}

class _State extends State<AmbassadorProfileScreen> {
  final _profileRepo = ProfileRepository();
  final _amRepo      = AmbassadorRepository(ApiClient.dio);

  Map<String, dynamic>? _user;
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _profileRepo.getMe(),
        _amRepo.getStats(),
      ]);
      if (mounted) {
        setState(() {
          _user  = results[0];
          _stats = results[1];
          _loading = false;
        });
      }
    } catch (_) {
      final cached = await AuthStorage.getUser();
      if (mounted) {
        setState(() { _user = cached; _loading = false; });
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await _confirm(
      title: 'Déconnexion',
      message: 'Vous allez être déconnecté de votre espace ambassadeur.',
      actionLabel: 'Déconnexion',
      danger: false,
    );
    if (confirmed != true) return;
    await AuthStorage.clear();
    if (mounted) context.go('/phone');
  }

  Future<void> _deleteAccount() async {
    final confirmed = await _confirm(
      title: 'Supprimer le compte',
      message: 'Cette action est irréversible. Votre compte et toutes vos données seront effacés.',
      actionLabel: 'Supprimer',
      danger: true,
    );
    if (confirmed != true) return;
    try {
      await ApiClient.dio.delete('/users/me');
      await AuthStorage.clear();
      if (mounted) context.go('/phone');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
      }
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String actionLabel,
    required bool danger,
  }) => showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF0F2942))),
      content: Text(message, style: const TextStyle(color: Color(0xFF6B7280), height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler', style: TextStyle(color: AppColors.primaryMid)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(actionLabel,
            style: TextStyle(
              color: danger ? Colors.red : AppColors.primaryMid,
              fontWeight: FontWeight.w700,
            )),
        ),
      ],
    ),
  );

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final name            = _user?['name']            as String? ?? '—';
    final phone           = _user?['phone']           as String? ?? '—';
    final status          = _user?['ambassadorStatus'] as String? ?? 'PENDING';
    final companyName     = _user?['companyName']     as String?;
    final ninea           = _user?['ninea']            as String?;
    final rccm            = _user?['rccm']             as String?;
    final cniRecto        = _user?['cniRecto']        as String?;
    final cniVerso        = _user?['cniVerso']        as String?;
    final fleetSize       = (_stats?['fleetSize']     as num?)?.toInt() ?? 0;
    final fleetMax        = (_stats?['fleetMax']      as num?)?.toInt() ?? 10;
    final activeCount     = (_stats?['activeCount']   as num?)?.toInt() ?? 0;
    final pendingCount    = (_stats?['pendingCount']  as num?)?.toInt() ?? 0;
    final totalCourses    = (_stats?['totalCourses']  as num?)?.toInt() ?? 0;

    final initials = name.trim().isNotEmpty
        ? name.trim().split(' ').take(2).map((w) => w[0].toUpperCase()).join()
        : '?';

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [

          // ── SliverAppBar gradient ──────────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: AppColors.primaryDark,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Actualiser',
                onPressed: _load,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Avatar
                      Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.50), width: 2),
                        ),
                        child: Center(
                          child: Text(initials, style: const TextStyle(
                            color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
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

                // ── Stats ────────────────────────────────────────────────
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
                    Text('Flotte : $fleetSize / $fleetMax',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF0F2942))),
                    const Spacer(),
                    Text('$fleetSize/$fleetMax',
                      style: TextStyle(color: AppColors.primaryMid.withValues(alpha: 0.70), fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fleetMax > 0 ? fleetSize / fleetMax : 0,
                      minHeight: 6,
                      backgroundColor: const Color(0xFFE5E7EB),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        fleetSize >= fleetMax ? Colors.orange : AppColors.primary),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),

                // ── Informations personnelles ─────────────────────────────
                _SectionHeader(title: 'Informations personnelles', icon: Icons.person_outline),
                const SizedBox(height: 10),
                _InfoCard(children: [
                  _InfoRow(icon: Icons.person_outline,   label: 'Nom',       value: name),
                  const Divider(height: 16),
                  _InfoRow(icon: Icons.phone_outlined,   label: 'Téléphone', value: phone),
                ]),
                const SizedBox(height: 20),

                // ── Entreprise ────────────────────────────────────────────
                if (companyName != null || ninea != null || rccm != null) ...[
                  _SectionHeader(title: 'Entreprise', icon: Icons.business_outlined),
                  const SizedBox(height: 10),
                  _InfoCard(children: [
                    if (companyName != null) _InfoRow(icon: Icons.store_outlined, label: 'Nom', value: companyName),
                    if (companyName != null && (ninea != null || rccm != null)) const Divider(height: 16),
                    if (ninea != null) _InfoRow(icon: Icons.tag, label: 'NINEA', value: ninea),
                    if (ninea != null && rccm != null) const Divider(height: 16),
                    if (rccm != null)  _InfoRow(icon: Icons.article_outlined, label: 'RCCM', value: rccm),
                  ]),
                  const SizedBox(height: 20),
                ],

                // ── Documents ─────────────────────────────────────────────
                _SectionHeader(title: 'Documents', icon: Icons.badge_outlined),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _DocThumb(url: cniRecto, label: 'CNI recto')),
                  const SizedBox(width: 12),
                  Expanded(child: _DocThumb(url: cniVerso, label: 'CNI verso')),
                ]),
                const SizedBox(height: 28),

                // ── Actions ───────────────────────────────────────────────
                _SectionHeader(title: 'Compte', icon: Icons.settings_outlined),
                const SizedBox(height: 10),
                _ActionTile(
                  icon: Icons.logout,
                  label: 'Déconnexion',
                  color: AppColors.primaryMid,
                  onTap: _logout,
                ),
                const SizedBox(height: 8),
                _ActionTile(
                  icon: Icons.delete_outline,
                  label: 'Supprimer mon compte',
                  color: Colors.red,
                  onTap: _deleteAccount,
                ),

              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    final map = {
      'ACTIVE':   (Colors.green, Icons.check_circle,        'Compte actif'),
      'PENDING':  (Colors.orange, Icons.hourglass_top_rounded, 'En attente de validation'),
      'REJECTED': (Colors.red,   Icons.cancel_outlined,     'Dossier refusé'),
    };
    final s = map[status] ?? (Colors.grey, Icons.help_outline, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: s.$1.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: s.$1.withValues(alpha: 0.50)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(s.$2, size: 14, color: Colors.white),
        const SizedBox(width: 6),
        Text(s.$3, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _MiniStat({required this.label, required this.value, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
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
  final String title;
  final IconData icon;
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
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE5E7EB)),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6)],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
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
  final String? url;
  final String label;
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
            ? GestureDetector(
                onTap: () {/* open full screen */},
                child: Image.network(
                  url!,
                  height: 100,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) => _placeholder(),
                ),
              )
            : _placeholder(),
      ),
    ],
  );

  Widget _placeholder() => Container(
    height: 100,
    width: double.infinity,
    decoration: BoxDecoration(
      color: const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
    ),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade400, size: 28),
      const SizedBox(height: 4),
      Text('Non fourni', style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
    ]),
  );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
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
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: color)),
          const Spacer(),
          Icon(Icons.chevron_right, color: Colors.grey.shade300, size: 20),
        ]),
      ),
    ),
  );
}
