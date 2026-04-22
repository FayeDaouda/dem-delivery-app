import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/api_client.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/theme/app_theme.dart';
import 'document_upload_screen.dart';
import 'driver_order_history_screen.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});
  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  Map<String, dynamic>? _user;
  String? _photoPath;
  static const _photoKey = 'driver_profile_photo';

  @override
  void initState() {
    super.initState();
    _load();
    // Rebuild quand la langue change
    LocaleService.notifier.addListener(_onLangChange);
  }

  @override
  void dispose() {
    LocaleService.notifier.removeListener(_onLangChange);
    super.dispose();
  }

  void _onLangChange() => setState(() {});

  Future<void> _load() async {
    final user  = await AuthStorage.getUser();
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() { _user = user; _photoPath = prefs.getString(_photoKey); });
  }

  Future<void> _pickProfilePhoto() async {
    final source = await _showPhotoSourceSheet();
    if (source == null) return;
    final file = await ImagePicker().pickImage(source: source, imageQuality: 80);
    if (file == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_photoKey, file.path);
    if (mounted) setState(() => _photoPath = file.path);
  }

  Future<ImageSource?> _showPhotoSourceSheet() {
    final s = AppStrings.current;
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _GradientSheet(children: [
        _SheetTitle(s.changePhoto),
        const SizedBox(height: 16),
        _SheetBtn(icon: Icons.camera_alt_outlined,    label: s.takePhoto,   onTap: () => Navigator.pop(context, ImageSource.camera)),
        const SizedBox(height: 10),
        _SheetBtn(icon: Icons.photo_library_outlined, label: s.fromGallery, onTap: () => Navigator.pop(context, ImageSource.gallery)),
      ]),
    );
  }

  Future<void> _logout() async {
    await AuthStorage.clear();
    if (mounted) context.go('/phone');
  }

  Future<void> _deleteAccount() async {
    final s = AppStrings.current;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 22),
            const SizedBox(width: 8),
            Text(s.deleteAccountTitle,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
          ],
        ),
        content: Text(s.deleteAccountWarning,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel,
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.deleteAccountConfirm,
                style: const TextStyle(
                    color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ApiClient.dio.delete('/users/me');
      await AuthStorage.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.current.deleteAccountSuccess),
            backgroundColor: AppColors.primary,
          ),
        );
        context.go('/phone');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  bool get _isMoto => _user?['vehicleType'] == 'MOTO';

  // ── Statut documents ───────────────────────────────────────────────────────
  bool get _hasIdCard  => _user?['idCardFront'] != null && _user?['idCardBack'] != null;
  bool get _hasLicense => _user?['licenseFront'] != null && _user?['licenseBack'] != null;

  // ── Support ────────────────────────────────────────────────────────────────
  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showSupportSheet() {
    final s = AppStrings.current;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _GradientSheet(children: [
        const Icon(Icons.support_agent_outlined, color: Colors.white, size: 40),
        const SizedBox(height: 8),
        const Text('Support DEM',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        _SupportTile(icon: Icons.phone_outlined,      label: s.callSupport, sub: '+221 78 000 00 00', onTap: () => _launch('tel:+221780000000')),
        const SizedBox(height: 10),
        _SupportTile(icon: Icons.email_outlined,      label: s.sendEmail,   sub: 'support@dem.sn',   onTap: () => _launch('mailto:support@dem.sn')),
        const SizedBox(height: 10),
        _SupportTile(icon: Icons.chat_bubble_outline, label: s.whatsapp,    sub: '+221 78 000 00 00', onTap: () => _launch('https://wa.me/221780000000')),
      ]),
    );
  }

  // ── Langue ─────────────────────────────────────────────────────────────────
  void _showLanguageSheet() {
    final s = AppStrings.current;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) {
          final cur = LocaleService.current;
          return _GradientSheet(children: [
            Text(s.language,
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _LangTile(flag: '🇫🇷', label: s.french,  code: 'fr', selected: cur == 'fr', onTap: () async { final nav = Navigator.of(ctx); await LocaleService.setLang('fr'); setSt(() {}); nav.pop(); }),
            const SizedBox(height: 8),
            _LangTile(flag: '🇬🇧', label: s.english, code: 'en', selected: cur == 'en', onTap: () async { final nav = Navigator.of(ctx); await LocaleService.setLang('en'); setSt(() {}); nav.pop(); }),
            const SizedBox(height: 8),
            _LangTile(flag: '🇸🇳', label: s.wolof,   code: 'wo', selected: cur == 'wo', onTap: () async { final nav = Navigator.of(ctx); await LocaleService.setLang('wo'); setSt(() {}); nav.pop(); }),
          ]);
        },
      ),
    );
  }

  // ── Demande changement numéro ──────────────────────────────────────────────
  void _showEditPhone() {
    final s       = AppStrings.current;
    final pending = _user?['pendingPhone'] as String?;
    final status  = _user?['phoneChangeStatus'] as String?;
    final requestedAtRaw = _user?['phoneChangeRequestedAt'] as String?;

    // 1. Demande déjà en cours → info + numéro en attente
    if (status == 'PENDING' && pending != null) {
      _showPhoneChangeInfo(
        icon: Icons.schedule_outlined,
        iconColor: const Color(0xFFF59E0B),
        title: 'Demande en cours',
        message: 'Votre demande de changement de numéro est en attente de validation par l\'administrateur.\n\n📞 $pending',
      );
      return;
    }

    // 2. Cooldown 7 jours — calcul côté Flutter (confirmé aussi côté serveur)
    if (requestedAtRaw != null) {
      final requestedAt = DateTime.tryParse(requestedAtRaw);
      if (requestedAt != null) {
        final daysSince = DateTime.now().difference(requestedAt).inDays;
        if (daysSince < 7) {
          final daysLeft = 7 - daysSince;
          _showPhoneChangeInfo(
            icon: Icons.lock_clock_outlined,
            iconColor: const Color(0xFFEF4444),
            title: 'Modification indisponible',
            message: 'Vous avez déjà soumis une demande récemment.\n\nVous pourrez en soumettre une nouvelle dans $daysLeft jour${daysLeft > 1 ? 's' : ''}.',
          );
          return;
        }
      }
    }

    // 3. Formulaire de demande
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF0CB8DE), Color(0xFF0671BA), Color(0xFF04317C)],
            ),
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.editPhone,
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              // Bandeau info admin
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'La demande sera examinée par l\'administrateur avant d\'être appliquée. Une seule demande est possible par semaine.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '77 123 45 67',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
                  prefixText: '+221 ',
                  prefixStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(s.cancel,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.65))),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () async {
                      final phone = ctrl.text.trim();
                      if (phone.length < 8) return;
                      Navigator.pop(context);
                      try {
                        await ApiClient.dio.post('/users/driver/phone-change', data: {'newPhone': '+221$phone'});
                        await _load();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Demande envoyée — en attente de validation admin'),
                              backgroundColor: Color(0xFF22C55E),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
                          );
                        }
                      }
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    child: Text(s.save,
                        style: const TextStyle(
                            color: Color(0xFF04317C), fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPhoneChangeInfo({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
          ],
        ),
        content: Text(message, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final s        = AppStrings.current;
    final name     = _user?['name']  as String? ?? 'Driver';
    final phone    = _user?['phone'] as String? ?? '';
    final plate    = _user?['vehiclePlate'] as String? ?? '—';
    final verified = _user?['isVerified'] == true;
    final pending  = _user?['pendingPhone'] as String?;
    final phoneChangeStatus = _user?['phoneChangeStatus'] as String?;

    return Scaffold(
      body: Column(
        children: [
          // ── Header ──
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
                        IconButton(onPressed: () => context.pop(),
                            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20)),
                        const Spacer(),
                        Text(s.myProfile,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        IconButton(onPressed: _showSupportSheet,
                            icon: const Icon(Icons.headset_mic_outlined, color: Colors.white, size: 22)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Avatar modifiable
                  GestureDetector(
                    onTap: _pickProfilePhoto,
                    child: Stack(
                      children: [
                        Container(
                          width: 88, height: 88,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                          ),
                          child: _photoPath != null && File(_photoPath!).existsSync()
                              ? ClipOval(child: Image.file(File(_photoPath!), fit: BoxFit.cover))
                              : Icon(_isMoto ? Icons.motorcycle : Icons.directions_car_outlined,
                                  color: Colors.white, size: 40),
                        ),
                        Positioned(
                          right: 0, bottom: 0,
                          child: Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              color: AppColors.primary, shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_isMoto ? 'DEM Livraison' : 'DEM Thiak Thiak',
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // ── Corps ──
          Expanded(
            child: Container(
              color: AppColors.surface,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [

                  // Informations
                  _Section(title: s.information, children: [
                    _InfoRow(icon: Icons.phone_outlined, label: s.phoneNumber, value: phone),
                    _divider(),
                    _InfoRow(icon: _isMoto ? Icons.motorcycle : Icons.directions_car_outlined,
                        label: s.plate, value: plate),
                    _divider(),
                    _InfoRow(icon: Icons.verified_outlined, label: s.statusLabel,
                        value: verified ? s.verified : s.notVerified,
                        valueColor: verified ? const Color(0xFF22C55E) : const Color(0xFFEF4444)),
                    // Badge numéro en attente
                    if (pending != null && phoneChangeStatus == 'PENDING') ...[
                      _divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.schedule_outlined, color: Color(0xFFF59E0B), size: 18),
                            const SizedBox(width: 10),
                            Expanded(child: Text(s.phonePending,
                                style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 13))),
                            Text(pending, style: const TextStyle(
                                color: Color(0xFFF59E0B), fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 16),

                  // Documents
                  _Section(title: s.documents, children: [
                    _DocRow(label: s.idCard,  icon: Icons.badge_outlined,       verified: _hasIdCard,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DocumentUploadScreen())).then((_) => _load())),
                    _divider(),
                    _DocRow(label: s.license, icon: Icons.credit_card_outlined, verified: _hasLicense,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DocumentUploadScreen())).then((_) => _load())),
                  ]),
                  const SizedBox(height: 16),

                  // Activité
                  _Section(title: s.activity, children: [
                    _ActionRow(icon: Icons.history, label: s.historyTitle,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverOrderHistoryScreen()))),
                  ]),
                  const SizedBox(height: 16),

                  // Paramètres
                  _Section(title: s.settings, children: [
                    _ActionRow(icon: Icons.edit_outlined,     label: s.editPhone, onTap: _showEditPhone),
                    _divider(),
                    _ActionRow(icon: Icons.language_outlined, label: s.language,
                        trailing: LocaleService.current == 'en' ? '🇬🇧 EN' : LocaleService.current == 'wo' ? '🇸🇳 WO' : '🇫🇷 FR',
                        onTap: _showLanguageSheet),
                    _divider(),
                    _ActionRow(icon: Icons.support_agent_outlined, label: s.support, onTap: _showSupportSheet),
                    _divider(),
                    _ActionRow(icon: Icons.privacy_tip_outlined, label: s.privacyPolicy,
                        onTap: () => _launch('https://fayedaouda.github.io/dem-legal/privacy.html')),
                    _divider(),
                    _ActionRow(icon: Icons.description_outlined, label: s.termsOfService,
                        onTap: () => _launch('https://fayedaouda.github.io/dem-legal/terms.html')),
                  ]),
                  const SizedBox(height: 16),

                  // Compte
                  _Section(title: s.account, children: [
                    _ActionRow(icon: Icons.logout, label: s.logout,
                        color: Colors.redAccent, onTap: _logout),
                    _divider(),
                    _ActionRow(icon: Icons.delete_outline, label: s.deleteAccount,
                        color: const Color(0xFFEF4444), onTap: _deleteAccount),
                  ]),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Divider(
    height: 1, indent: 52, endIndent: 16,
    color: AppColors.primary.withValues(alpha: 0.08),
  );
}

// ── Widgets helpers ───────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title.toUpperCase(),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
        child: Column(children: children),
      ),
    ],
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoRow({required this.icon, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(children: [
      Icon(icon, color: AppColors.primary, size: 20),
      const SizedBox(width: 14),
      Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
      const Spacer(),
      Text(value, style: TextStyle(
          color: valueColor ?? AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
    ]),
  );
}

class _DocRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool verified;
  final VoidCallback onTap;
  const _DocRow({required this.label, required this.icon, required this.verified, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 14),
        Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: (verified ? const Color(0xFF22C55E) : const Color(0xFFF59E0B)).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(verified ? Icons.check_circle_outline : Icons.upload_outlined,
                size: 13, color: verified ? const Color(0xFF22C55E) : const Color(0xFFF59E0B)),
            const SizedBox(width: 4),
            Text(verified ? AppStrings.current.docVerified : AppStrings.current.docPending,
                style: TextStyle(
                    color: verified ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
                    fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(width: 6),
        const Icon(Icons.arrow_forward_ios, color: AppColors.textSecondary, size: 12),
      ]),
    ),
  );
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final String? trailing;
  const _ActionRow({required this.icon, required this.label, required this.onTap, this.color, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: TextStyle(color: c, fontSize: 14, fontWeight: FontWeight.w500))),
          if (trailing != null) ...[
            Text(trailing!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(width: 6),
          ],
          Icon(Icons.arrow_forward_ios, color: c.withValues(alpha: 0.4), size: 14),
        ]),
      ),
    );
  }
}

class _GradientSheet extends StatelessWidget {
  final List<Widget> children;
  const _GradientSheet({required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF0CB8DE), Color(0xFF0671BA), Color(0xFF04317C)],
      ),
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewPadding.bottom + 28),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      _DragHandle(),
      ...children,
    ]),
  );
}

class _SheetTitle extends StatelessWidget {
  final String text;
  const _SheetTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700));
}

class _SheetBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SheetBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Row(children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 14),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 15)),
      ]),
    ),
  );
}

class _LangTile extends StatelessWidget {
  final String flag;
  final String label;
  final String code;
  final bool selected;
  final VoidCallback onTap;
  const _LangTile({required this.flag, required this.label, required this.code, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: selected
            ? Colors.white.withValues(alpha: 0.20)
            : Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? Colors.white.withValues(alpha: 0.50) : Colors.white.withValues(alpha: 0.18),
        ),
      ),
      child: Row(children: [
        Text(flag, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 14),
        Expanded(child: Text(label, style: TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
        ))),
        if (selected)
          const Icon(Icons.check_circle, color: Colors.white, size: 20),
      ]),
    ),
  );
}

class _SupportTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;
  const _SupportTile({required this.icon, required this.label, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(children: [
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          Text(sub, style: TextStyle(color: Colors.white.withValues(alpha: 0.60), fontSize: 12)),
        ])),
        Icon(Icons.arrow_forward_ios, color: Colors.white.withValues(alpha: 0.50), size: 13),
      ]),
    ),
  );
}

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 36, height: 4,
    margin: const EdgeInsets.only(bottom: 16),
    decoration: BoxDecoration(
      color: AppColors.textSecondary.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

