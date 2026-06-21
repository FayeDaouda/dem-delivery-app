import 'dart:io';
import '../../../core/error/app_exception.dart';
import '../../../core/router/app_startup_notifier.dart';
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/api_client.dart';
import '../../../core/config/app_config.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/services/badge_service.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/referral_card.dart';
import '../data/profile_repository.dart';
import 'document_upload_screen.dart';
import 'driver_order_history_screen.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});
  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  Map<String, dynamic>? _user;
  List<Map<String, dynamic>>? _badgesConfig;
  String? _photoPath;
  static const _photoKey = 'driver_profile_photo';
  final _profileRepo    = ProfileRepository();
  final _scrollCtrl     = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    LocaleService.notifier.addListener(_onLangChange);
  }

  @override
  void dispose() {
    LocaleService.notifier.removeListener(_onLangChange);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onLangChange() => setState(() {});



  Future<void> _load() async {
    final user  = await AuthStorage.getUser();
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() { _user = user; _photoPath = prefs.getString(_photoKey); });
    final badges = await _profileRepo.getBadgesConfig();
    if (mounted) {
      setState(() {
        _badgesConfig = badges;
      });
    }
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
    appStartupNotifier.markLoggedOut();
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
      appStartupNotifier.markLoggedOut();
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
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  bool get _isMoto => _user?['vehicleType'] == 'MOTO';

  // ── Statut documents (7 champs, 5 groupes logiques) ──────────────────────────
  int get _docsUploaded {
    final fields = ['licenseFront','licenseBack','carteGrise','carteGriseBack','assurance','vehiclePhoto','avatar'];
    return fields.where((f) => _user?[f] != null).length;
  }
  static const int _docsTotal = 7;

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
        _SupportTile(icon: Icons.phone_outlined,      label: s.callSupport, sub: '+221 78 444 85 24', onTap: () => _launch('tel:+221784448524')),
        const SizedBox(height: 10),
        _SupportTile(icon: Icons.email_outlined,      label: s.sendEmail,   sub: 'support@dem.sn',   onTap: () => _launch('mailto:support@dem.sn')),
        const SizedBox(height: 10),
        _SupportTile(icon: Icons.chat_bubble_outline, label: s.whatsapp,    sub: '+221 78 444 85 24', onTap: () => _launch('https://wa.me/221784448524')),
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
            _LangTile(label: s.french,  code: 'fr', selected: cur == 'fr', onTap: () async { final nav = Navigator.of(ctx); await LocaleService.setLang('fr'); setSt(() {}); nav.pop(); }),
            const SizedBox(height: 8),
            _LangTile(label: s.english, code: 'en', selected: cur == 'en', onTap: () async { final nav = Navigator.of(ctx); await LocaleService.setLang('en'); setSt(() {}); nav.pop(); }),
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
                            SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.redAccent),
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

  void _showEditPlate() {
    final ctrl = TextEditingController(text: _user?['vehiclePlate'] as String? ?? '');
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
              const Text('Plaque d\'immatriculation',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(color: Colors.white, letterSpacing: 2, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Ex : DK 1234 AB',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
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
                    child: Text(AppStrings.current.cancel,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.65))),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () async {
                      final plate = ctrl.text.trim().toUpperCase();
                      if (plate.isEmpty) return;
                      Navigator.pop(context);
                      try {
                        await ApiClient.dio.patch('/users/me/profile', data: {'vehiclePlate': plate});
                        await _load();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Plaque mise à jour'),
                              backgroundColor: Color(0xFF22C55E),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.redAccent),
                          );
                        }
                      }
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    child: Text(AppStrings.current.save,
                        style: const TextStyle(color: Color(0xFF04317C), fontWeight: FontWeight.w700)),
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
    final driverStatus = _user?['driverStatus'] as String?;
    final isVerified   = _user?['isVerified'] == true;
    // Statut affiché : basé sur driverStatus (anciens drivers sans driverStatus → isVerified)
    final String statusLabel;
    final Color  statusColor;
    switch (driverStatus) {
      case 'VERIFIED':
        statusLabel = 'Vérifié ✓';         statusColor = const Color(0xFF22C55E);
      case 'UNDER_REVIEW':
        statusLabel = 'En cours de vérification'; statusColor = const Color(0xFFF59E0B);
      case 'PENDING_DOCUMENTS':
        statusLabel = 'Documents requis ⏰'; statusColor = const Color(0xFFFF9800);
      case 'SUSPENDED':
        statusLabel = 'Compte suspendu';    statusColor = const Color(0xFFEF4444);
      case 'INCOMPLETE':
        statusLabel = 'Profil incomplet';   statusColor = const Color(0xFF7B8CA0);
      default:
        // Ancien driver sans driverStatus → on se base sur isVerified
        statusLabel = isVerified ? 'Vérifié ✓' : 'Profil incomplet';
        statusColor = isVerified ? const Color(0xFF22C55E) : const Color(0xFF7B8CA0);
    }
    final pending  = _user?['pendingPhone'] as String?;
    final phoneChangeStatus = _user?['phoneChangeStatus'] as String?;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      body: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          SliverAppBar(
            expandedHeight: _user != null ? 420 : 280,
            pinned: true,
            floating: false,
            stretch: true,
            backgroundColor: AppColors.primaryMid,
            leading: IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            ),
            title: Text(s.myProfile, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            centerTitle: true,
            actions: [
              IconButton(onPressed: _showSupportSheet, icon: const Icon(Icons.headset_mic_outlined, color: Colors.white, size: 22)),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 56),
                    child: Column(children: [
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: _pickProfilePhoto,
                        child: Stack(children: [
                          Container(
                            width: 88, height: 88,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                            ),
                            child: _photoPath != null && File(_photoPath!).existsSync()
                                ? ClipOval(child: Image.file(File(_photoPath!), fit: BoxFit.cover))
                                : Icon(_isMoto ? Icons.motorcycle : Icons.directions_car_outlined, color: Colors.white, size: 40),
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
                        ]),
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
                        child: Text(_isMoto ? 'Livreur-DEM' : 'DEM Thiak Thiak',
                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                      ),
                      if (_user != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          child: _BadgeCard(user: _user!, badgesConfig: _badgesConfig),
                        )
                      else
                        const SizedBox(height: 16),
                    ]),
                  ),
                ),
              ),
            ),
          ),

          // ── Corps ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                  // Parrainage
                  Text('PARRAINAGE',
                      style: const TextStyle(color: Color(0xFF7B8CA0), fontSize: 11,
                          fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  ReferralCard(referralCode: _user?['referralCode'] as String?),
                  const SizedBox(height: 16),

                  // Informations
                  _Section(title: s.information, children: [
                    _InfoRow(icon: Icons.phone_outlined, label: s.phoneNumber, value: phone),
                    _divider(),
                    _EditableInfoRow(
                      icon: _isMoto ? Icons.motorcycle : Icons.directions_car_outlined,
                      label: s.plate,
                      value: plate,
                      onTap: _showEditPlate,
                    ),
                    _divider(),
                    _InfoRow(icon: Icons.verified_outlined, label: s.statusLabel,
                        value: statusLabel, valueColor: statusColor),
                    // Mes Documents — ligne unique avec barre de progression
                    _divider(),
                    _DocsProgressRow(
                      uploaded: _docsUploaded,
                      total:    _docsTotal,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DocumentUploadScreen())).then((_) => _load()),
                    ),
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
                        trailing: LocaleService.current == 'en' ? 'EN' : 'FR',
                        onTap: _showLanguageSheet),
                    _divider(),
                    _ActionRow(icon: Icons.support_agent_outlined, label: s.support, onTap: _showSupportSheet),
                    _divider(),
                    _ActionRow(icon: Icons.privacy_tip_outlined, label: s.privacyPolicy,
                        onTap: () => _launch(AppConfig.privacyPolicyUrl)),
                    _divider(),
                    _ActionRow(icon: Icons.description_outlined, label: s.termsOfService,
                        onTap: () => _launch(AppConfig.termsUrl)),
                  ]),
                  const SizedBox(height: 16),

                  // Compte
                  _Section(title: 'Gestion du compte', children: [
                    _ActionRow(icon: Icons.logout, label: s.logout,
                        color: Colors.redAccent, onTap: _logout),
                    _divider(),
                    _ActionRow(icon: Icons.delete_outline, label: s.deleteAccount,
                        color: const Color(0xFFEF4444), onTap: _deleteAccount),
                  ]),
                  const SizedBox(height: 12),
              ]),
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
          style: const TextStyle(color: Color(0xFF7B8CA0), fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
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
      Text(label, style: const TextStyle(color: Color(0xFF7B8CA0), fontSize: 14)),
      const Spacer(),
      Text(value, style: TextStyle(
          color: valueColor ?? const Color(0xFF1A1A2E), fontSize: 14, fontWeight: FontWeight.w600)),
    ]),
  );
}

class _EditableInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  const _EditableInfoRow({required this.icon, required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 14),
        Text(label, style: const TextStyle(color: Color(0xFF7B8CA0), fontSize: 14)),
        const Spacer(),
        Text(value, style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        const Icon(Icons.edit_outlined, color: AppColors.primary, size: 15),
      ]),
    ),
  );
}

// ── Ligne "Mes Documents" avec barre de progression ───────────────────────────
class _DocsProgressRow extends StatelessWidget {
  final int uploaded;
  final int total;
  final VoidCallback onTap;
  const _DocsProgressRow({required this.uploaded, required this.total, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final allDone = uploaded == total;
    final progress = total > 0 ? uploaded / total : 0.0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(Icons.folder_open_outlined, color: AppColors.primary, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('Mes Documents',
                      style: TextStyle(color: Color(0xFF1A1A2E), fontSize: 14)),
                  const Spacer(),
                  Text('$uploaded/$total',
                      style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: allDone ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
                      )),
                ]),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: const Color(0xFFE5E7EB),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      allDone ? const Color(0xFF22C55E) : AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.arrow_forward_ios, color: Color(0xFF7B8CA0), size: 12),
        ]),
      ),
    );
  }
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
    final c = color ?? const Color(0xFF1A1A2E);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(icon, color: color ?? AppColors.primary, size: 20),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: TextStyle(color: c, fontSize: 14, fontWeight: FontWeight.w500))),
          if (trailing != null) ...[
            Text(trailing!, style: const TextStyle(color: Color(0xFF7B8CA0), fontSize: 13)),
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
  final String label;
  final String code;
  final bool selected;
  final VoidCallback onTap;
  const _LangTile({required this.label, required this.code, required this.selected, required this.onTap});

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

// ── Carte badge driver ────────────────────────────────────────────────────────
class _BadgeCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final List<Map<String, dynamic>>? badgesConfig;
  const _BadgeCard({required this.user, this.badgesConfig});

  @override
  Widget build(BuildContext context) {
    final courses   = (user['completedCourses'] as num?)?.toInt() ?? 0;
    final referrals = (user['referralCount']    as num?)?.toInt() ?? 0;
    final rating    = (user['averageRating']    as num?)?.toDouble() ?? 0.0;

    final badge     = BadgeService.compute(courses: courses, referrals: referrals, rating: rating, remoteConfig: badgesConfig);
    final nextBadge = BadgeService.next(badge.tier);
    final progress  = BadgeService.progressToCourses(courses: courses, current: badge.tier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            // Badge actuel
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: badge.color.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(badge.icon, color: badge.color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(badge.name,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                      Text(badge.subtitle,
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Stats ligne
            Row(
              children: [
                _StatChip(icon: Icons.two_wheeler, value: '$courses', label: 'courses'),
                const SizedBox(width: 8),
                _StatChip(icon: Icons.person_add_outlined, value: '$referrals', label: 'parrainages'),
                const SizedBox(width: 8),
                _StatChip(
                  icon: Icons.star_rounded,
                  value: rating > 0 ? rating.toStringAsFixed(1) : '—',
                  label: 'note',
                  iconColor: const Color(0xFFFFD700),
                ),
              ],
            ),

            // Barre de progression vers le prochain badge
            if (nextBadge != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // GAUCHE : courses actuelles + objectif
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$courses courses',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                      Text('Objectif : ${nextBadge.coursesRequired} courses',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.60), fontSize: 10)),
                    ],
                  ),
                  const Spacer(),
                  // DROITE : icon + nom du prochain badge
                  Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: nextBadge.color.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(nextBadge.icon, color: nextBadge.color, size: 13),
                  ),
                  const SizedBox(width: 6),
                  Text(nextBadge.name,
                      style: TextStyle(color: nextBadge.color, fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(nextBadge.color),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Carte forfait journalier (S4 — pas encore intégrée dans le profil) ────────
// ignore: unused_element
class _ForfaitCard extends StatelessWidget {
  final Map<String, dynamic> status;
  const _ForfaitCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final active       = status['active'] as bool? ?? false;
    final amount       = (status['amount'] as num?)?.toInt() ?? 480;
    final totalOwed    = (status['totalOwed'] as num?)?.toInt() ?? 0;
    final todayCharged = status['todayCharged'] as bool? ?? false;

    // Si forfait inactif → petite bannière info discrète
    if (!active) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Forfait journalier non encore activé (S4)',
              style: TextStyle(color: Color(0xFF7B8CA0), fontSize: 13),
            ),
          ),
        ]),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        // En-tête
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            gradient: AppColors.gradientSplash,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            const Icon(Icons.receipt_long_outlined, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            const Text('Forfait journalier',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$amount FCFA/jour',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        // Corps
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            // Total dû
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('TOTAL DÛ',
                    style: TextStyle(color: Color(0xFF7B8CA0), fontSize: 10,
                        fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                const SizedBox(height: 4),
                Text('$totalOwed FCFA',
                    style: TextStyle(
                      color: totalOwed > 0 ? const Color(0xFFEF4444) : const Color(0xFF22C55E),
                      fontSize: 20, fontWeight: FontWeight.w800,
                    )),
              ]),
            ),
            // Statut aujourd'hui
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (todayCharged ? const Color(0xFFEF4444) : const Color(0xFF22C55E))
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (todayCharged ? const Color(0xFFEF4444) : const Color(0xFF22C55E))
                      .withValues(alpha: 0.30),
                ),
              ),
              child: Column(children: [
                Icon(
                  todayCharged ? Icons.check_circle_outline : Icons.radio_button_unchecked,
                  size: 16,
                  color: todayCharged ? const Color(0xFFEF4444) : const Color(0xFF22C55E),
                ),
                const SizedBox(height: 3),
                Text(
                  todayCharged ? 'Débité' : 'Non débité',
                  style: TextStyle(
                    color: todayCharged ? const Color(0xFFEF4444) : const Color(0xFF22C55E),
                    fontSize: 10, fontWeight: FontWeight.w700,
                  ),
                ),
                Text("Aujourd'hui",
                    style: const TextStyle(color: Color(0xFF7B8CA0), fontSize: 9)),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? iconColor;
  const _StatChip({required this.icon, required this.value, required this.label, this.iconColor});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, size: 14, color: iconColor ?? Colors.white.withValues(alpha: 0.80)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 9)),
        ],
      ),
    ),
  );
}

