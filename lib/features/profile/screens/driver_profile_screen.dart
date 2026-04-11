import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/theme/app_theme.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  Map<String, dynamic>? _user;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = await AuthStorage.getUser();
    if (mounted) setState(() => _user = user);
  }

  Future<void> _logout() async {
    await AuthStorage.clear();
    if (mounted) context.go('/phone');
  }

  bool get _isMoto => _user?['vehicleType'] == 'MOTO';

  @override
  Widget build(BuildContext context) {
    final name = _user?['name'] as String? ?? 'Driver';
    final phone = _user?['phone'] as String? ?? '';
    final plate = _user?['vehiclePlate'] as String? ?? '—';

    return Scaffold(
      body: Column(
        children: [
          // ── Header gradient ──
          Container(
            decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // Barre top
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                        ),
                        const Spacer(),
                        const Text(
                          'Mon profil',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Avatar
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Icon(
                      _isMoto ? Icons.motorcycle : Icons.directions_car_outlined,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    name,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _isMoto ? 'DEM Livraison' : 'DEM Thiak Thiak',
                      style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),

          // ── Contenu ──
          Expanded(
            child: Container(
              color: AppColors.surface,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Infos
                  _Section(title: 'Informations', children: [
                    _InfoRow(icon: Icons.phone_outlined, label: 'Téléphone', value: '+221 $phone'),
                    _InfoRow(
                      icon: _isMoto ? Icons.motorcycle : Icons.directions_car_outlined,
                      label: 'Plaque',
                      value: plate,
                    ),
                    _InfoRow(
                      icon: Icons.verified_outlined,
                      label: 'Statut',
                      value: _user?['isVerified'] == true ? 'Vérifié ✓' : 'Non vérifié',
                    ),
                  ]),

                  const SizedBox(height: 16),

                  // Historique
                  _Section(title: 'Activité', children: [
                    _ActionRow(
                      icon: Icons.history,
                      label: 'Historique des courses',
                      onTap: () {}, // TODO: page historique
                    ),
                    _ActionRow(
                      icon: Icons.star_outline,
                      label: 'Mes évaluations',
                      onTap: () {},
                    ),
                  ]),

                  const SizedBox(height: 16),

                  // Déconnexion
                  _Section(title: 'Compte', children: [
                    _ActionRow(
                      icon: Icons.logout,
                      label: 'Se déconnecter',
                      color: Colors.redAccent,
                      onTap: _logout,
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 14),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          const Spacer(),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _ActionRow({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(color: c, fontSize: 14, fontWeight: FontWeight.w500)),
            const Spacer(),
            Icon(Icons.arrow_forward_ios, color: c.withValues(alpha: 0.5), size: 14),
          ],
        ),
      ),
    );
  }
}
