import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
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
  bool _isLoading       = false;
  bool _uploadingAvatar = false;
  bool _headerCollapsed = false;
  final _picker            = ImagePicker();
  final _scrollController  = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadUser();
    _fetchProfile();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final collapsed = _scrollController.offset > 70;
    if (collapsed != _headerCollapsed) setState(() => _headerCollapsed = collapsed);
  }

  Future<void> _loadUser() async {
    final user = await AuthStorage.getUser();
    if (mounted) setState(() => _user = user);
  }

  Future<void> _fetchProfile() async {
    try {
      final res = await ApiClient.dio.get('/users/me');
      if (res.statusCode == 200) {
        final data = res.data['data'] ?? res.data as Map<String, dynamic>;
        await AuthStorage.saveUser(data);
        if (mounted) setState(() { _user = data; _badgeData = data['clientBadgeData'] as Map<String, dynamic>?; });
      }
    } catch (_) {}
  }

  // ── Avatar ──────────────────────────────────────────────────────────────────
  Future<void> _pickAvatar() async {
    final src = await showModalBottomSheet<ImageSource>(
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
      if (url != null && mounted) setState(() => _user?['avatar'] = url);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur lors de l\'envoi de la photo.')));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  // ── Edit profil (nom + email) ────────────────────────────────────────────────
  Future<void> _editProfile() async {
    final nameCtrl  = TextEditingController(text: _user?['name']  as String? ?? '');
    final emailCtrl = TextEditingController(text: _user?['email'] as String? ?? '');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).viewPadding.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Modifier mon profil', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          _EditField(ctrl: nameCtrl,  label: 'Nom complet', icon: Icons.person_outline),
          const SizedBox(height: 12),
          _EditField(ctrl: emailCtrl, label: 'Email',       icon: Icons.email_outlined, keyboard: TextInputType.emailAddress),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ]),
      ),
    );
    if (ok != true) return;
    try {
      final res = await ApiClient.dio.patch('/users/me/profile', data: {
        if (nameCtrl.text.trim().isNotEmpty)  'name':  nameCtrl.text.trim(),
        if (emailCtrl.text.trim().isNotEmpty) 'email': emailCtrl.text.trim(),
      });
      final updated = res.data['user'] as Map<String, dynamic>?;
      if (updated != null && mounted) {
        await AuthStorage.saveUser(updated);
        setState(() => _user = updated);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  // ── Demande changement numéro ────────────────────────────────────────────────
  Future<void> _requestPhoneChange() async {
    final ctrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).viewPadding.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Changer de numéro', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('La demande sera validée par notre équipe sous 24–48h.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
              child: const Text('+221', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _EditField(ctrl: ctrl, label: 'Nouveau numéro', icon: Icons.phone_outlined, keyboard: TextInputType.phone),
            ),
          ]),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text('Envoyer la demande', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ]),
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      await ApiClient.dio.post('/users/client/phone-change', data: {
        'newPhone': '+221${ctrl.text.replaceAll(RegExp(r'\s'), '').replaceFirst('+221', '')}',
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demande envoyée. Vous serez contacté sous 24–48h.')),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  // ── Support ──────────────────────────────────────────────────────────────────
  void _showSupport() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          gradient: AppColors.gradientSplash,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewPadding.bottom + 36),
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
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer mon compte ?',
            style: TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.w700)),
        content: const Text('Cette action est irréversible. Toutes vos données seront effacées.',
            style: TextStyle(color: Color(0xFF7B8CA0))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler', style: TextStyle(color: AppColors.primary))),
          TextButton(onPressed: () => Navigator.pop(ctx, true),  child: const Text('Supprimer', style: TextStyle(color: Color(0xFFEF4444)))),
        ],
      ),
    );
    if (confirm != true) return;
    if (mounted) setState(() => _isLoading = true);
    try {
      await ApiClient.dio.delete('/users/me');
    } catch (_) {}
    await AuthStorage.clear();
    if (mounted) context.go('/phone');
  }

  // ── BUILD ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4F6FA),
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final name     = _user?['name']  as String? ?? 'Client';
    final phone    = _user?['phone'] as String? ?? '';
    final email    = _user?['email'] as String?;
    final avatar   = _user?['avatar'] as String?;
    final initials = name.trim().isNotEmpty
        ? name.trim().split(' ').take(2).map((w) => w[0].toUpperCase()).join()
        : '?';
    final phoneStatus = _user?['phoneChangeStatus'] as String?;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      body: Column(children: [

        // ── Header collapsible ────────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top bar — toujours visible
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(children: [
                    IconButton(
                      onPressed: () => context.go('/client/home'),
                      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                    ),
                    // Petit avatar affiché uniquement quand le header est replié
                    AnimatedSize(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeInOut,
                      child: _headerCollapsed
                          ? Padding(
                              padding: const EdgeInsets.only(left: 4, right: 6),
                              child: ClipOval(
                                child: Container(
                                  width: 30, height: 30,
                                  color: Colors.white.withValues(alpha: 0.15),
                                  child: avatar != null
                                      ? Image.network(avatar, fit: BoxFit.cover, width: 30, height: 30,
                                          errorBuilder: (_, e, s) => Center(
                                            child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))))
                                      : Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const Spacer(),
                    const Text('Mon compte', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(
                      onPressed: _showSupport,
                      icon: const Icon(Icons.support_agent_outlined, color: Colors.white, size: 22),
                      tooltip: 'Support',
                    ),
                  ]),
                ),

                // Section dépliable : avatar + nom + téléphone + email
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: _headerCollapsed
                      ? const SizedBox.shrink()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 8),
                            // Avatar cliquable
                            GestureDetector(
                              onTap: _uploadingAvatar ? null : _pickAvatar,
                              child: Stack(children: [
                                Container(
                                  width: 88, height: 88,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 3),
                                    color: Colors.white.withValues(alpha: 0.15),
                                  ),
                                  child: _uploadingAvatar
                                      ? const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                      : avatar != null
                                          ? ClipOval(child: Image.network(avatar, fit: BoxFit.cover, width: 88, height: 88,
                                              errorBuilder: (_, e, s) => Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)))))
                                          : Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800))),
                                ),
                                Positioned(
                                  bottom: 0, right: 0,
                                  child: Container(
                                    width: 26, height: 26,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppColors.primaryMid, width: 1.5),
                                    ),
                                    child: const Icon(Icons.camera_alt, size: 13, color: AppColors.primaryMid),
                                  ),
                                ),
                              ]),
                            ),
                            const SizedBox(height: 10),
                            Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(phone, style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13)),
                            if (email != null) ...[
                              const SizedBox(height: 2),
                              Text(email, style: TextStyle(color: Colors.white.withValues(alpha: 0.60), fontSize: 12)),
                            ],
                            const SizedBox(height: 20),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),

        // ── Corps scrollable ──────────────────────────────────────────────────
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchProfile,
            color: AppColors.primary,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                // ── 1. Badge ──────────────────────────────────────────────────
                if (_badgeData != null) ...[
                  _SectionLabel(label: 'MON BADGE'),
                  ClientBadgeCard(badgeData: _badgeData!),
                  const SizedBox(height: 20),
                ],

                // ── 2. Parrainage ────────────────────────────────────────────
                _SectionLabel(label: 'PARRAINAGE'),
                ReferralCard(referralCode: _user?['referralCode'] as String?),
                const SizedBox(height: 20),

                // ── 3. Activité ──────────────────────────────────────────────
                _SectionLabel(label: 'ACTIVITÉ'),
                _MenuItem(
                  icon: Icons.list_alt_outlined,
                  title: 'Mes commandes',
                  onTap: () => context.push('/orders/my'),
                ),
                const SizedBox(height: 20),

                // ── 4. Mon profil ────────────────────────────────────────────
                _SectionLabel(label: 'MON PROFIL'),
                _MenuGroup(items: [
                  _MenuItemData(
                    icon: Icons.person_outline,
                    title: 'Modifier nom & email',
                    onTap: _editProfile,
                  ),
                  _MenuItemData(
                    icon: Icons.place_outlined,
                    title: 'Mes adresses favorites',
                    onTap: () => context.push('/client/favorite-addresses'),
                  ),
                  _MenuItemData(
                    icon: Icons.phone_outlined,
                    title: phoneStatus == 'PENDING'
                        ? 'Changement de numéro en cours…'
                        : 'Demander un changement de numéro',
                    onTap: phoneStatus == 'PENDING' ? () {} : _requestPhoneChange,
                    titleColor: phoneStatus == 'PENDING' ? Colors.grey : const Color(0xFF1A1A2E),
                    iconColor:  phoneStatus == 'PENDING' ? Colors.grey : AppColors.primary,
                  ),
                ]),
                const SizedBox(height: 20),

                // ── 5. Support ───────────────────────────────────────────────
                _SectionLabel(label: 'SUPPORT'),
                _MenuGroup(items: [
                  _MenuItemData(icon: Icons.support_agent_outlined, title: 'Contacter DEM', onTap: _showSupport),
                ]),
                const SizedBox(height: 20),

                // ── 6. Informations ──────────────────────────────────────────
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

                // ── 7. Compte ────────────────────────────────────────────────
                _SectionLabel(label: 'COMPTE'),
                _MenuGroup(items: [
                  _MenuItemData(icon: Icons.logout_outlined, title: 'Déconnexion', onTap: _handleLogout),
                ]),
                const SizedBox(height: 12),
                _MenuGroup(items: [
                  _MenuItemData(
                    icon: Icons.delete_outline,
                    title: 'Supprimer mon compte',
                    titleColor: const Color(0xFFEF4444),
                    iconColor:  const Color(0xFFEF4444),
                    onTap: _handleDeleteAccount,
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets locaux
// ─────────────────────────────────────────────────────────────────────────────

class _EditField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final TextInputType keyboard;
  const _EditField({required this.ctrl, required this.label, required this.icon, this.keyboard = TextInputType.text});
  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    keyboardType: keyboard,
    style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A2E)),
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 18, color: AppColors.primaryMid),
      filled: true,
      fillColor: const Color(0xFFF1F5F9),
      labelStyle: const TextStyle(color: Color(0xFF7B8CA0), fontSize: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
  );
}

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

class _SupportTile extends StatelessWidget {
  final IconData icon; final String label, sub; final VoidCallback onTap;
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

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(label, style: const TextStyle(color: Color(0xFF7B8CA0), fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
  );
}

class _MenuItemData {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color titleColor;
  final Color iconColor;
  const _MenuItemData({
    required this.icon, required this.title, required this.onTap,
    this.titleColor = const Color(0xFF1A1A2E),
    this.iconColor  = AppColors.primary,
  });
}

class _MenuGroup extends StatelessWidget {
  final List<_MenuItemData> items;
  const _MenuGroup({required this.items});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: Column(children: [
      for (int i = 0; i < items.length; i++) ...[
        if (i > 0) const Divider(height: 1, indent: 52, color: Color(0xFFEEF0F5)),
        _MenuItem(
          icon: items[i].icon, title: items[i].title, onTap: items[i].onTap,
          titleColor: items[i].titleColor, iconColor: items[i].iconColor,
          standalone: false,
        ),
      ],
    ]),
  );
}

class _MenuItem extends StatelessWidget {
  final IconData icon; final String title; final VoidCallback onTap;
  final Color titleColor, iconColor; final bool standalone;
  const _MenuItem({
    required this.icon, required this.title, required this.onTap,
    this.titleColor = const Color(0xFF1A1A2E),
    this.iconColor  = AppColors.primary,
    this.standalone = true,
  });
  @override
  Widget build(BuildContext context) {
    Widget child = InkWell(
      onTap: onTap,
      borderRadius: standalone ? BorderRadius.circular(16) : BorderRadius.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.10), shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(title, style: TextStyle(color: titleColor, fontSize: 15, fontWeight: FontWeight.w500))),
          const Icon(Icons.chevron_right, color: Color(0xFFBCC5D0), size: 20),
        ]),
      ),
    );
    if (!standalone) return child;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(16), child: child),
    );
  }
}
