import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/referral_card.dart';
import '../home_client/widgets/client_badge_card.dart';

class ClientProfileScreen extends StatefulWidget {
  const ClientProfileScreen({super.key});

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _badgeData;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _fetchProfile();
  }

  Future<void> _loadUser() async {
    final user = await AuthStorage.getUser();
    if (mounted) setState(() => _user = user);
  }

  Future<void> _fetchProfile() async {
    try {
      final response = await ApiClient.dio.get('/users/me');
      if (response.statusCode == 200) {
        final userData = response.data['data'] ?? response.data as Map<String, dynamic>;
        await AuthStorage.saveUser(userData);
        if (mounted) {
          setState(() {
            _user      = userData;
            _badgeData = userData['clientBadgeData'] as Map<String, dynamic>?;
          });
        }
      }
    } catch (_) {}
  }

  void _showSupport() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          gradient: AppColors.gradientSplash,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Icon(Icons.support_agent_outlined, color: Colors.white, size: 40),
          const SizedBox(height: 8),
          const Text('Support DEM', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          _SupportTile(icon: Icons.phone_outlined,      label: 'Appeler le support', sub: '+221 78 000 00 00', onTap: () => _launch('tel:+221780000000')),
          const SizedBox(height: 10),
          _SupportTile(icon: Icons.email_outlined,      label: 'Envoyer un e-mail',  sub: 'support@dem.sn',   onTap: () => _launch('mailto:support@dem.sn')),
          const SizedBox(height: 10),
          _SupportTile(icon: Icons.chat_bubble_outline, label: 'WhatsApp',           sub: '+221 78 000 00 00', onTap: () => _launch('https://wa.me/221780000000')),
        ]),
      ),
    );
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _handleLogout() async {
    await AuthStorage.clear();
    if (mounted) context.go('/phone');
  }

  Future<void> _handleDeleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer mon compte ?',
            style: TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.w700)),
        content: const Text(
          'Cette action est irréversible. Toutes vos données seront effacées.',
          style: TextStyle(color: Color(0xFF7B8CA0)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler', style: TextStyle(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (mounted) setState(() => _isLoading = true);

    try {
      await ApiClient.dio.delete('/users/me');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    } finally {
      await AuthStorage.clear();
      if (mounted) context.go('/phone');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4F6FA),
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final name = _user?['name'] ?? _user?['firstName'] ?? 'Client';
    final phone = _user?['phone'] ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      body: Column(
        children: [
          // ── Header gradient ──
          Container(
            decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => context.go('/client/home'),
                          icon: const Icon(Icons.arrow_back_ios_new,
                              color: Colors.white, size: 20),
                        ),
                        const Spacer(),
                        const Text('Mon compte',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Avatar
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    child: const Icon(Icons.person, size: 44, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  Text(name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(phone,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75), fontSize: 14)),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // ── Corps ──
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionLabel(label: 'ACTIVITÉ'),
                  _MenuItem(
                    icon: Icons.list_alt_outlined,
                    title: 'Mes commandes',
                    onTap: () => context.push('/orders/my'),
                  ),
                  const SizedBox(height: 20),

                  // ── Badge ──
                  if (_badgeData != null) ...[
                    _SectionLabel(label: 'MON BADGE'),
                    ClientBadgeCard(badgeData: _badgeData!),
                    const SizedBox(height: 20),
                  ],

                  _SectionLabel(label: 'PARRAINAGE'),
                  ReferralCard(referralCode: _user?['referralCode'] as String?),
                  const SizedBox(height: 20),

                  _SectionLabel(label: 'SUPPORT'),
                  _MenuGroup(items: [
                    _MenuItemData(
                      icon: Icons.support_agent_outlined,
                      title: 'Contacter DEM',
                      onTap: _showSupport,
                    ),
                  ]),
                  const SizedBox(height: 20),

                  _SectionLabel(label: 'INFORMATIONS'),
                  _MenuGroup(items: [
                    _MenuItemData(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Politique de confidentialité',
                      onTap: () => _launch(AppConfig.privacyPolicyUrl),
                    ),
                    _MenuItemData(
                      icon: Icons.description_outlined,
                      title: 'Conditions d\'utilisation',
                      onTap: () => _launch(AppConfig.termsUrl),
                    ),
                  ]),
                  const SizedBox(height: 20),

                  _SectionLabel(label: 'COMPTE'),
                  _MenuGroup(items: [
                    _MenuItemData(
                      icon: Icons.logout_outlined,
                      title: 'Déconnexion',
                      onTap: _handleLogout,
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _MenuGroup(items: [
                    _MenuItemData(
                      icon: Icons.delete_outline,
                      title: 'Supprimer mon compte',
                      titleColor: const Color(0xFFEF4444),
                      iconColor: const Color(0xFFEF4444),
                      onTap: _handleDeleteAccount,
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

// ── Support tile (utilisé dans le bottom sheet) ───────────────────────────────
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
            Text(sub,   style: TextStyle(color: Colors.white.withValues(alpha: 0.70), fontSize: 12)),
          ]),
          const Spacer(),
          Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.50), size: 20),
        ]),
      ),
    ),
  );
}

// ── Section label ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(label,
          style: const TextStyle(
              color: Color(0xFF7B8CA0), fontSize: 11, fontWeight: FontWeight.w600,
              letterSpacing: 0.8)),
    );
  }
}

// ── Menu group (card with dividers) ──────────────────────────────────────────
class _MenuItemData {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color titleColor;
  final Color iconColor;

  const _MenuItemData({
    required this.icon,
    required this.title,
    required this.onTap,
    this.titleColor = const Color(0xFF1A1A2E),
    this.iconColor = AppColors.primary,
  });
}

class _MenuGroup extends StatelessWidget {
  final List<_MenuItemData> items;
  const _MenuGroup({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, indent: 52, color: Color(0xFFEEF0F5)),
            _MenuItem(
              icon: items[i].icon,
              title: items[i].title,
              onTap: items[i].onTap,
              titleColor: items[i].titleColor,
              iconColor: items[i].iconColor,
              standalone: false,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Menu item ─────────────────────────────────────────────────────────────────
class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color titleColor;
  final Color iconColor;
  final bool standalone;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.titleColor = const Color(0xFF1A1A2E),
    this.iconColor = AppColors.primary,
    this.standalone = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget child = InkWell(
      onTap: onTap,
      borderRadius: standalone ? BorderRadius.circular(16) : BorderRadius.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      color: titleColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w500)),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFBCC5D0), size: 20),
          ],
        ),
      ),
    );

    if (standalone) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: child,
        ),
      );
    }
    return child;
  }
}
