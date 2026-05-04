import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../admin_session.dart';
import 'admin_acquisition_screen.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});
  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
    _fetch();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await AdminSession.dio.get(
        '/admin/drivers',
        queryParameters: {'status': 'phone-change', 'limit': '50'},
      );
      final drivers = (res.data['drivers'] as List)
          .cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() { _requests = drivers; _loading = false; });
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.response?.data?['message'] ?? 'Erreur de chargement';
          _loading = false;
        });
      }
    }
  }

  Future<void> _resolve(String driverId, bool approve) async {
    try {
      await AdminSession.dio.patch(
        '/admin/drivers/$driverId/phone-change',
        data: {'approve': approve},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(approve ? 'Numéro approuvé ✓' : 'Demande refusée'),
          backgroundColor: approve ? const Color(0xFF22C55E) : Colors.redAccent,
        ));
      }
      await _fetch();
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.response?.data?['message'] ?? 'Erreur'),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  void _logout() {
    AdminSession.clear();
    context.go('/phone');
  }

  @override
  Widget build(BuildContext context) {
    final adminName = AdminSession.admin?['name'] as String? ?? 'Admin';

    return Scaffold(
      body: Column(
        children: [
          // ── Header ──
          Container(
            decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.admin_panel_settings_outlined,
                              color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Panel Admin',
                                  style: TextStyle(color: Colors.white70, fontSize: 11,
                                      fontWeight: FontWeight.w500)),
                              Text(adminName,
                                  style: const TextStyle(color: Colors.white,
                                      fontSize: 16, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _logout,
                          icon: const Icon(Icons.logout, color: Colors.white70, size: 20),
                          tooltip: 'Déconnexion',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Compteur demandes
                    if (_tabCtrl.index == 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.phone_forwarded_outlined,
                                color: Colors.white, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              _loading
                                  ? 'Chargement…'
                                  : '${_requests.length} demande${_requests.length != 1 ? 's' : ''} en attente',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ── TabBar ──
          Container(
            color: AppColors.surface,
            child: TabBar(
              controller: _tabCtrl,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              indicatorColor: Colors.white,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              tabs: const [
                Tab(text: 'DEMANDES'),
                Tab(text: 'ACQUISITION'),
              ],
            ),
          ),

          // ── Corps ──
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                // Onglet 1 : demandes changement numéro
                Container(
                  color: AppColors.surface,
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                      : _error != null
                          ? _buildError()
                          : _requests.isEmpty
                              ? _buildEmpty()
                              : RefreshIndicator(
                                  color: AppColors.primary,
                                  onRefresh: _fetch,
                                  child: ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                                    itemCount: _requests.length,
                                    itemBuilder: (_, i) =>
                                        _RequestCard(driver: _requests[i], onResolve: _resolve),
                                  ),
                                ),
                ),
                // Onglet 2 : acquisition
                const AdminAcquisitionScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_outline,
            color: const Color(0xFF22C55E).withValues(alpha: 0.6), size: 64),
        const SizedBox(height: 12),
        const Text('Aucune demande en attente',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
      ],
    ),
  );

  Widget _buildError() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.wifi_off_outlined, color: AppColors.textSecondary, size: 48),
        const SizedBox(height: 12),
        Text(_error!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _fetch,
          child: const Text('Réessayer', style: TextStyle(color: AppColors.primary)),
        ),
      ],
    ),
  );
}

// ── Carte demande ─────────────────────────────────────────────────────────────
class _RequestCard extends StatefulWidget {
  final Map<String, dynamic> driver;
  final Future<void> Function(String id, bool approve) onResolve;
  const _RequestCard({required this.driver, required this.onResolve});

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _busy = false;

  Future<void> _act(bool approve) async {
    setState(() => _busy = true);
    await widget.onResolve(widget.driver['id'] as String, approve);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final name        = widget.driver['name']        as String? ?? '—';
    final phone       = widget.driver['phone']       as String? ?? '—';
    final pending     = widget.driver['pendingPhone'] as String? ?? '—';
    final vehicleType = widget.driver['vehicleType'] as String? ?? 'MOTO';
    final isMoto      = vehicleType == 'MOTO';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── En-tête driver ──
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isMoto ? Icons.motorcycle : Icons.directions_car_outlined,
                    color: AppColors.primary, size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      Text(isMoto ? 'DEM Livraison' : 'DEM Thiak Thiak',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('En attente',
                      style: TextStyle(
                          color: Color(0xFFF59E0B), fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0x1A000000)),
            const SizedBox(height: 14),

            // ── Numéros ──
            Row(
              children: [
                Expanded(
                  child: _PhoneChip(
                    label: 'Numéro actuel',
                    phone: phone,
                    color: AppColors.textSecondary,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward,
                      color: AppColors.textSecondary.withValues(alpha: 0.5), size: 16),
                ),
                Expanded(
                  child: _PhoneChip(
                    label: 'Nouveau numéro',
                    phone: pending,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Actions ──
            _busy
                ? const Center(
                    child: SizedBox(
                      height: 32, width: 32,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    ),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _ActionBtn(
                          label: 'Refuser',
                          color: const Color(0xFFEF4444),
                          icon: Icons.close_rounded,
                          onTap: () => _act(false),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ActionBtn(
                          label: 'Approuver',
                          color: const Color(0xFF22C55E),
                          icon: Icons.check_rounded,
                          onTap: () => _act(true),
                        ),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}

class _PhoneChip extends StatelessWidget {
  final String label;
  final String phone;
  final Color color;
  const _PhoneChip({required this.label, required this.phone, required this.color});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
          style: TextStyle(
              color: AppColors.textSecondary.withValues(alpha: 0.7),
              fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
      const SizedBox(height: 4),
      Text(phone,
          style: TextStyle(
              color: color, fontSize: 13, fontWeight: FontWeight.w700)),
    ],
  );
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.label, required this.color, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    ),
  );
}
