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
import '../../../core/theme/client_text.dart';
import '../../../core/utils/dem_toast.dart';
import '../../../core/utils/input_formatters.dart';
import '../../../shared/widgets/gradient_dialog.dart';
import '../../../shared/widgets/gradient_sheet.dart';
import '../../../shared/widgets/referral_card.dart';
import '../../../shared/widgets/swipe_to_confirm.dart';
import '../data/profile_repository.dart';
import 'document_upload_screen.dart';
import 'driver_order_history_screen.dart';
import 'driver_scheduled_orders_screen.dart';
import 'driver_settings_screen.dart';
import 'driver_wallet_screen.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});
  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

// ── Même architecture que ClientProfileScreen : header gradient qui se
// replie au scroll (AnimatedSize, pas de SliverAppBar à hauteur fixe) +
// corps en cartes groupées. Évite par construction toute la classe de bug
// "overflow de hauteur figée" qu'avait l'ancien SliverAppBar/expandedHeight
// dès que la carte badge grandissait (plusieurs critères restants).
class _DriverProfileScreenState extends State<DriverProfileScreen> {
  Map<String, dynamic>? _user;
  List<Map<String, dynamic>>? _badgesConfig;
  String? _photoPath;
  static const _photoKey = 'driver_profile_photo';
  final _profileRepo = ProfileRepository();
  final _scrollCtrl = ScrollController();

  bool _headerCollapsed = false;

  void _onScroll() {
    final collapsed = _scrollCtrl.offset > 70;
    if (collapsed != _headerCollapsed) setState(() => _headerCollapsed = collapsed);
  }

  // ── Confirmation déconnexion/suppression (glisser pour confirmer) ────────
  bool _logoutLoading  = false;
  bool _deleteLoading  = false;
  int  _logoutSwipeTick = 0;
  int  _deleteSwipeTick = 0;

  @override
  void initState() {
    super.initState();
    _load();
    LocaleService.notifier.addListener(_onLangChange);
    _scrollCtrl.addListener(_onScroll);
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewPadding.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: const Icon(Icons.logout_rounded, color: AppColors.primary, size: 26),
              ),
              const SizedBox(height: 14),
              const Text('Se déconnecter ?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textDark)),
              const SizedBox(height: 6),
              const Text(
                'Vous devrez vous reconnecter avec votre numéro de téléphone pour reprendre vos courses.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4),
              ),
              const SizedBox(height: 24),
              SwipeToConfirm(
                key: ValueKey('logout-$_logoutSwipeTick'),
                label: 'Glissez pour se déconnecter',
                loading: _logoutLoading,
                trackColor: AppColors.primary,
                thumbColor: Colors.white,
                iconColor: AppColors.primary,
                labelColor: Colors.white,
                onConfirmed: () async {
                  setSheetState(() => _logoutLoading = true);
                  try {
                    await AuthStorage.clear();
                    appStartupNotifier.markLoggedOut();
                    if (mounted) {
                      Navigator.pop(ctx);
                      context.go('/phone');
                    }
                  } catch (e) {
                    setSheetState(() {
                      _logoutLoading = false;
                      _logoutSwipeTick++;
                    });
                    if (mounted) showDemToast(context, friendlyError(e), isError: true);
                  }
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _logoutLoading ? null : () => Navigator.pop(ctx),
                child: const Text('Annuler', style: TextStyle(color: AppColors.textMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final s = AppStrings.current;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewPadding.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: const Icon(Icons.delete_forever_outlined, color: AppColors.error, size: 28),
              ),
              const SizedBox(height: 14),
              Text(s.deleteAccountTitle,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textDark)),
              const SizedBox(height: 6),
              Text(s.deleteAccountWarning,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4)),
              const SizedBox(height: 24),
              SwipeToConfirm(
                key: ValueKey('delete-$_deleteSwipeTick'),
                label: 'Glissez pour supprimer',
                loading: _deleteLoading,
                trackColor: AppColors.error,
                thumbColor: Colors.white,
                iconColor: AppColors.error,
                labelColor: Colors.white,
                onConfirmed: () async {
                  setSheetState(() => _deleteLoading = true);
                  try {
                    await ApiClient.dio.delete('/users/me');
                    await AuthStorage.clear();
                    appStartupNotifier.markLoggedOut();
                    if (mounted) {
                      Navigator.pop(ctx);
                      showDemToast(context, s.deleteAccountSuccess);
                      context.go('/phone');
                    }
                  } catch (e) {
                    setSheetState(() {
                      _deleteLoading = false;
                      _deleteSwipeTick++;
                    });
                    if (mounted) showDemToast(context, friendlyError(e), isError: true);
                  }
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _deleteLoading ? null : () => Navigator.pop(ctx),
                child: Text(s.cancel, style: const TextStyle(color: AppColors.textMuted)),
              ),
            ],
          ),
        ),
      ),
    );
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
        showDemToast(context, 'Impossible d\'ouvrir la page', isError: true);
      }
    } catch (_) {
      if (mounted) {
        showDemToast(context, 'Impossible d\'ouvrir la page', isError: true);
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
        Text('Support DEM',
            style: ClientText.title.copyWith(color: Colors.white)),
        const SizedBox(height: 20),
        _SupportTile(icon: Icons.phone_outlined,      label: s.callSupport, sub: '+221 71 006 46 64', onTap: () => _launch('tel:+221710064664')),
        const SizedBox(height: 10),
        _SupportTile(icon: Icons.email_outlined,      label: s.sendEmail,   sub: 'support@dem.sn',   onTap: () => _launch('mailto:support@dem.sn')),
        const SizedBox(height: 10),
        _SupportTile(icon: Icons.chat_bubble_outline, label: s.whatsapp,    sub: '+221 71 006 46 64', onTap: () => _launch('https://wa.me/221710064664')),
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
                style: ClientText.sheetTitle.copyWith(color: Colors.white)),
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
        iconColor: AppColors.pending,
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
            iconColor: AppColors.error,
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
      builder: (_) {
        bool saving = false;
        return StatefulBuilder(builder: (ctx, setDialogState) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          decoration: BoxDecoration(
            gradient: AppColors.gradientDialog,
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.editPhone,
                  style: ClientText.sheetTitle.copyWith(color: Colors.white)),
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
                    onPressed: saving ? null : () => Navigator.pop(context),
                    child: Text(s.cancel,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.65))),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: saving ? null : () async {
                      final phone = ctrl.text.trim();
                      if (phone.length < 8) return;
                      setDialogState(() => saving = true);
                      try {
                        await ApiClient.dio.post('/users/driver/phone-change', data: {'newPhone': '+221$phone'});
                        await _load();
                        if (mounted) {
                          Navigator.pop(context);
                          showDemToast(context, 'Demande envoyée — en attente de validation admin');
                        }
                      } catch (e) {
                        setDialogState(() => saving = false);
                        if (mounted) {
                          showDemToast(context, friendlyError(e), isError: true);
                        }
                      }
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    child: saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryDark))
                        : Text(s.save,
                            style: const TextStyle(
                                color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ));
      },
    );
  }

  void _showEditPlate() {
    final ctrl = TextEditingController(text: _user?['vehiclePlate'] as String? ?? '');
    showDialog(
      context: context,
      builder: (_) {
        bool saving = false;
        return StatefulBuilder(builder: (ctx, setDialogState) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          decoration: BoxDecoration(
            gradient: AppColors.gradientDialog,
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Plaque d\'immatriculation',
                  style: ClientText.sheetTitle.copyWith(color: Colors.white)),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [PlateInputFormatter()],
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
                    onPressed: saving ? null : () => Navigator.pop(context),
                    child: Text(AppStrings.current.cancel,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.65))),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: saving ? null : () async {
                      final plate = ctrl.text.trim().toUpperCase().replaceAll(' ', '');
                      if (plate.isEmpty) return;
                      setDialogState(() => saving = true);
                      try {
                        await ApiClient.dio.patch('/users/me/profile', data: {'vehiclePlate': plate});
                        await _load();
                        if (mounted) {
                          Navigator.pop(context);
                          showDemToast(context, 'Plaque mise à jour');
                        }
                      } catch (e) {
                        setDialogState(() => saving = false);
                        if (mounted) {
                          showDemToast(context, friendlyError(e), isError: true);
                        }
                      }
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    child: saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryDark))
                        : Text(AppStrings.current.save,
                            style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ));
      },
    );
  }

  void _showEditEmergencyContact() {
    final nameCtrl  = TextEditingController(text: _user?['emergencyContactName'] as String? ?? '');
    final phoneCtrl = TextEditingController(text: _user?['emergencyContactPhone'] as String? ?? '');
    showDialog(
      context: context,
      builder: (_) {
        bool saving = false;
        return StatefulBuilder(builder: (ctx, setDialogState) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Container(
          decoration: BoxDecoration(
            gradient: AppColors.gradientDialog,
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Contact d\'urgence',
                  style: ClientText.sheetTitle.copyWith(color: Colors.white)),
              const SizedBox(height: 6),
              Text('Prévenu en cas d\'alerte SOS pendant une course.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12.5)),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Nom (ex : Maman, Awa...)',
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
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Ex : +221771234567',
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
                    onPressed: saving ? null : () => Navigator.pop(context),
                    child: Text(AppStrings.current.cancel,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.65))),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: saving ? null : () async {
                      setDialogState(() => saving = true);
                      try {
                        await ApiClient.dio.patch('/users/me/profile', data: {
                          'emergencyContactName':  nameCtrl.text.trim(),
                          'emergencyContactPhone': phoneCtrl.text.trim(),
                        });
                        await _load();
                        if (mounted) {
                          Navigator.pop(context);
                          showDemToast(context, 'Contact d\'urgence mis à jour');
                        }
                      } catch (e) {
                        setDialogState(() => saving = false);
                        if (mounted) {
                          showDemToast(context, friendlyError(e), isError: true);
                        }
                      }
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    child: saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryDark))
                        : Text(AppStrings.current.save,
                            style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ));
      },
    );
  }

  void _showPhoneChangeInfo({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
  }) {
    showGradientInfoDialog(
      context,
      title: title,
      message: message,
      icon: icon,
      iconColor: iconColor,
      actionLabel: 'OK',
      onAction: () {},
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final s        = AppStrings.current;
    final name     = _user?['name']  as String? ?? 'Livreur';
    final phone    = _user?['phone'] as String? ?? '';
    final plate    = _user?['vehiclePlate'] as String? ?? '—';
    final driverStatus = _user?['driverStatus'] as String?;
    final isVerified   = _user?['isVerified'] == true;
    // Statut affiché : basé sur driverStatus (anciens drivers sans driverStatus → isVerified)
    final String statusLabel;
    final Color  statusColor;
    switch (driverStatus) {
      case 'VERIFIED':
        statusLabel = 'Vérifié ✓';         statusColor = AppColors.successLight;
      case 'UNDER_REVIEW':
        statusLabel = 'En cours de vérification'; statusColor = AppColors.pending;
      case 'PENDING_DOCUMENTS':
        statusLabel = 'Documents requis ⏰'; statusColor = AppColors.surge;
      case 'SUSPENDED':
        statusLabel = 'Compte suspendu';    statusColor = AppColors.error;
      case 'INCOMPLETE':
        statusLabel = 'Profil incomplet';   statusColor = AppColors.textMuted;
      default:
        // Ancien driver sans driverStatus → on se base sur isVerified
        statusLabel = isVerified ? 'Vérifié ✓' : 'Profil incomplet';
        statusColor = isVerified ? AppColors.successLight : AppColors.textMuted;
    }
    final pending  = _user?['pendingPhone'] as String?;
    final phoneChangeStatus = _user?['phoneChangeStatus'] as String?;
    final hasPhoto = _photoPath != null && File(_photoPath!).existsSync();

    return Scaffold(
      backgroundColor: AppColors.lightBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header gradient FULL WIDTH — même structure que le profil client ──
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
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => context.pop(),
                          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                        ),
                        // Petite photo affichée uniquement quand le header est replié
                        AnimatedSize(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeInOut,
                          child: _headerCollapsed
                              ? Padding(
                                  padding: const EdgeInsets.only(left: 4, right: 6),
                                  child: ClipOval(
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      color: Colors.white.withValues(alpha: 0.15),
                                      child: hasPhoto
                                          ? Image.file(File(_photoPath!), fit: BoxFit.cover, width: 30, height: 30)
                                          : Icon(_isMoto ? Icons.motorcycle : Icons.directions_car_outlined,
                                              color: Colors.white, size: 16),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        const Spacer(),
                        Text(s.myProfile, style: ClientText.subtitle.copyWith(color: Colors.white)),
                        const Spacer(),
                        IconButton(
                          onPressed: _showSupportSheet,
                          icon: const Icon(Icons.headset_mic_outlined, color: Colors.white, size: 22),
                          tooltip: 'Support',
                        ),
                      ],
                    ),
                  ),

                  // Section dépliable : photo + nom + badge "Livreur-DEM" + carte badge
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: _headerCollapsed
                        ? const SizedBox.shrink()
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 8),
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
                                    child: hasPhoto
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
                                child: const Text('Livreur-DEM',
                                    style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                              ),
                              if (_user != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                                  child: _BadgeCard(user: _user!, badgesConfig: _badgesConfig),
                                )
                              else
                                const SizedBox(height: 16),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),

          // ── Corps scrollable pleine largeur ──────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 1. Parrainage ────────────────────────────────────────────
                    const _SectionLabel(label: 'PARRAINAGE'),
                    ReferralCard(referralCode: _user?['referralCode'] as String?),
                    const SizedBox(height: 20),

                    // ── 2. Informations ──────────────────────────────────────────
                    const _SectionLabel(label: 'INFORMATIONS'),
                    _MenuCard(children: [
                      _InfoTile(icon: Icons.phone_outlined, label: s.phoneNumber, value: phone),
                      _menuDivider(),
                      _EditTile(
                        icon: _isMoto ? Icons.motorcycle : Icons.directions_car_outlined,
                        label: s.plate,
                        value: plate,
                        onTap: _showEditPlate,
                      ),
                      _menuDivider(),
                      _InfoTile(icon: Icons.verified_outlined, label: s.statusLabel,
                          value: statusLabel, valueColor: statusColor),
                      _menuDivider(),
                      _EditTile(
                        icon: Icons.emergency_outlined,
                        label: 'Contact d\'urgence',
                        value: (_user?['emergencyContactPhone'] as String?)?.isNotEmpty == true
                            ? (_user?['emergencyContactName'] as String?)?.isNotEmpty == true
                                ? _user!['emergencyContactName'] as String
                                : _user!['emergencyContactPhone'] as String
                            : 'Non configuré',
                        onTap: _showEditEmergencyContact,
                      ),
                      _menuDivider(),
                      _DocsProgressTile(
                        uploaded: _docsUploaded,
                        total:    _docsTotal,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DocumentUploadScreen())).then((_) => _load()),
                      ),
                      if (pending != null && phoneChangeStatus == 'PENDING') ...[
                        _menuDivider(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.schedule_outlined, color: AppColors.pending, size: 18),
                              const SizedBox(width: 10),
                              Expanded(child: Text(s.phonePending,
                                  style: const TextStyle(color: AppColors.pending, fontSize: 13))),
                              Text(pending, style: const TextStyle(
                                  color: AppColors.pending, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 20),

                    // ── 3. Activité ──────────────────────────────────────────────
                    const _SectionLabel(label: 'ACTIVITÉ'),
                    _MenuCard(children: [
                      _NavTile(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Portefeuille',
                        trailing: '${((_user?['balance'] as num?)?.toInt() ?? 0)} FCFA',
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverWalletScreen()))
                            .then((_) => _load()),
                      ),
                      _menuDivider(),
                      _NavTile(icon: Icons.history, label: s.historyTitle,
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverOrderHistoryScreen()))),
                      _menuDivider(),
                      _NavTile(icon: Icons.event_available_outlined, label: 'Courses programmées',
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverScheduledOrdersScreen()))),
                    ]),
                    const SizedBox(height: 20),

                    // ── 4. Paramètres ────────────────────────────────────────────
                    const _SectionLabel(label: 'PARAMÈTRES'),
                    _MenuCard(children: [
                      _NavTile(icon: Icons.edit_outlined, label: s.editPhone, onTap: _showEditPhone),
                      _menuDivider(),
                      _NavTile(icon: Icons.language_outlined, label: s.language,
                          trailing: LocaleService.current == 'en' ? 'EN' : 'FR',
                          onTap: _showLanguageSheet),
                      _menuDivider(),
                      _NavTile(icon: Icons.support_agent_outlined, label: s.support, onTap: _showSupportSheet),
                      _menuDivider(),
                      _NavTile(icon: Icons.help_outline, label: 'Questions fréquentes',
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverSettingsScreen()))),
                      _menuDivider(),
                      _NavTile(icon: Icons.privacy_tip_outlined, label: s.privacyPolicy,
                          onTap: () => _launch(AppConfig.privacyPolicyUrl)),
                      _menuDivider(),
                      _NavTile(icon: Icons.description_outlined, label: s.termsOfService,
                          onTap: () => _launch(AppConfig.termsUrl)),
                    ]),
                    const SizedBox(height: 20),

                    // ── 5. Compte ────────────────────────────────────────────────
                    const _SectionLabel(label: 'COMPTE'),
                    _MenuCard(children: [
                      _NavTile(icon: Icons.logout_outlined, label: s.logout, danger: true, onTap: _logout),
                    ]),
                    const SizedBox(height: 12),
                    _MenuCard(children: [
                      _NavTile(icon: Icons.delete_outline, label: s.deleteAccount, danger: true, onTap: _deleteAccount),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _menuDivider() => const Divider(height: 1, indent: 52, color: AppColors.lightBorder);

// ── Widgets helpers ───────────────────────────────────────────────────────────
// Même langage visuel que ClientProfileScreen (_SectionLabel/_MenuGroup/_MenuItem) :
// cartes blanches à coins arrondis, icône dans un rond translucide, divider indenté.

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      label,
      style: ClientText.caption.copyWith(color: AppColors.textMuted, letterSpacing: 0.8),
    ),
  );
}

class _MenuCard extends StatelessWidget {
  final List<Widget> children;
  const _MenuCard({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: AppShadows.card,
    ),
    child: Column(children: children),
  );
}

// Ligne d'information statique (non éditable) — valeur affichée à droite.
class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoTile({required this.icon, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    child: Row(children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.10), shape: BoxShape.circle),
        child: Icon(icon, color: AppColors.primary, size: 18),
      ),
      const SizedBox(width: 14),
      Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
      const Spacer(),
      Text(value, style: TextStyle(color: valueColor ?? AppColors.textDark, fontSize: 14, fontWeight: FontWeight.w600)),
    ]),
  );
}

// Ligne éditable — tape pour ouvrir la modification, valeur + icône crayon.
class _EditTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  const _EditTile({required this.icon, required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.10), shape: BoxShape.circle),
          child: Icon(icon, color: AppColors.primary, size: 18),
        ),
        const SizedBox(width: 14),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textDark, fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.edit_outlined, color: AppColors.primary, size: 15),
      ]),
    ),
  );
}

// Ligne de navigation — même comportement que _MenuItem côté client, avec en
// plus un texte "trailing" optionnel (solde, langue) et une variante danger
// (déconnexion/suppression de compte).
class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? trailing;
  final bool danger;
  const _NavTile({required this.icon, required this.label, required this.onTap, this.trailing, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final titleColor = danger ? AppColors.error : AppColors.textDark;
    final iconColor  = danger ? AppColors.error : AppColors.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.10), shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label, style: TextStyle(color: titleColor, fontSize: 15, fontWeight: FontWeight.w500)),
          ),
          if (trailing != null) ...[
            Text(trailing!, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(width: 6),
          ],
          const Icon(Icons.chevron_right, color: AppColors.lightIconMuted, size: 20),
        ]),
      ),
    );
  }
}

// ── Ligne "Mes Documents" avec barre de progression ───────────────────────────
class _DocsProgressTile extends StatelessWidget {
  final int uploaded;
  final int total;
  final VoidCallback onTap;
  const _DocsProgressTile({required this.uploaded, required this.total, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final allDone = uploaded == total;
    final progress = total > 0 ? uploaded / total : 0.0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.10), shape: BoxShape.circle),
            child: Icon(Icons.folder_open_outlined, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('Mes Documents',
                      style: TextStyle(color: AppColors.textDark, fontSize: 14)),
                  const Spacer(),
                  Text('$uploaded/$total',
                      style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: allDone ? AppColors.successLight : AppColors.pending,
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
                      allDone ? AppColors.successLight : AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.chevron_right, color: AppColors.lightIconMuted, size: 20),
        ]),
      ),
    );
  }
}

class _GradientSheet extends StatelessWidget {
  final List<Widget> children;
  const _GradientSheet({required this.children});

  @override
  Widget build(BuildContext context) => GradientSheet(
    blurred: false,
    bordered: false,
    radius: 24,
    padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewPadding.bottom + 28),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const SheetDragHandle(),
      ...children,
    ]),
  );
}

class _SheetTitle extends StatelessWidget {
  final String text;
  const _SheetTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: ClientText.sheetTitle.copyWith(color: Colors.white));
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
    final objective = nextBadge != null
        ? BadgeService.objectiveLabel(
            BadgeService.closestCriteria(nextBadge, courses: courses, referrals: referrals, rating: rating),
            courses: courses, referrals: referrals, rating: rating,
          )
        : '';

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
                  iconColor: AppColors.ratingGold,
                ),
              ],
            ),

            // Prochain badge : détail par critère (courses/parrainages/note)
            // plutôt qu'une seule barre mêlant plusieurs critères — jusqu'ici
            // impossible de savoir LEQUEL des critères manquait encore.
            if (nextBadge != null) ...[
              const SizedBox(height: 14),
              Divider(color: Colors.white.withValues(alpha: 0.15), height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Prochain niveau',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 11)),
                  const Spacer(),
                  Icon(nextBadge.icon, size: 14, color: nextBadge.color),
                  const SizedBox(width: 5),
                  Text(nextBadge.name,
                      style: TextStyle(color: nextBadge.color, fontSize: 13, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 12),
              if (_closestRow.coursesRequired > 0)
                _DriverCriterionBar(
                  icon: Icons.two_wheeler, label: 'Courses',
                  current: courses, needed: _closestRow.coursesRequired,
                  color: nextBadge.color,
                ),
              if (_closestRow.referralsRequired > 0) ...[
                const SizedBox(height: 10),
                _DriverCriterionBar(
                  icon: Icons.person_add_outlined, label: 'Parrainages',
                  current: referrals, needed: _closestRow.referralsRequired,
                  color: nextBadge.color,
                ),
              ],
              if (_closestRow.ratingRequired > 0) ...[
                const SizedBox(height: 10),
                _DriverRatingLine(
                  current: rating, needed: _closestRow.ratingRequired,
                  color: nextBadge.color,
                ),
              ],
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: nextBadge.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Icon(Icons.track_changes_rounded, size: 14, color: nextBadge.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Objectif le plus proche : $objective',
                        style: TextStyle(color: nextBadge.color, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: badge.color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.auto_awesome_rounded, size: 15, color: badge.color),
                  const SizedBox(width: 6),
                  Text('Niveau maximum atteint !',
                      style: TextStyle(color: badge.color, fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  BadgeCriteria get _closestRow {
    final courses   = (user['completedCourses'] as num?)?.toInt() ?? 0;
    final referrals = (user['referralCount']    as num?)?.toInt() ?? 0;
    final rating    = (user['averageRating']    as num?)?.toDouble() ?? 0.0;
    final badge     = BadgeService.compute(courses: courses, referrals: referrals, rating: rating, remoteConfig: badgesConfig);
    final nextBadge = BadgeService.next(badge.tier)!;
    return BadgeService.closestCriteria(nextBadge, courses: courses, referrals: referrals, rating: rating);
  }
}

// ── Barre de progression individuelle (thème sombre driver) ──────────────────
class _DriverCriterionBar extends StatelessWidget {
  final IconData icon;
  final String label;
  final int current, needed;
  final Color color;
  const _DriverCriterionBar({required this.icon, required this.label, required this.current, required this.needed, required this.color});

  @override
  Widget build(BuildContext context) {
    final ratio = needed > 0 ? (current / needed).clamp(0.0, 1.0) : 1.0;
    final done  = current >= needed;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 13, color: done ? AppColors.successLight : Colors.white.withValues(alpha: 0.75)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11, color: done ? AppColors.successLight : Colors.white.withValues(alpha: 0.75))),
        const Spacer(),
        if (done)
          Row(children: [
            Icon(Icons.check_circle, size: 13, color: AppColors.successLight),
            const SizedBox(width: 4),
            Text('Complété !', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.successLight)),
          ])
        else
          Text('$current / $needed', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: ratio,
          minHeight: 5,
          backgroundColor: Colors.white.withValues(alpha: 0.15),
          valueColor: AlwaysStoppedAnimation<Color>(done ? AppColors.successLight : color),
        ),
      ),
    ]);
  }
}

// ── Ligne note (thème sombre driver) ──────────────────────────────────────────
class _DriverRatingLine extends StatelessWidget {
  final double current, needed;
  final Color color;
  const _DriverRatingLine({required this.current, required this.needed, required this.color});

  @override
  Widget build(BuildContext context) {
    final ok = current >= needed;
    return Row(children: [
      Icon(ok ? Icons.star_rounded : Icons.star_outline_rounded,
          size: 14, color: ok ? AppColors.ratingGold : Colors.white.withValues(alpha: 0.75)),
      const SizedBox(width: 5),
      Text('Note moyenne', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.75))),
      const Spacer(),
      Text(current.toStringAsFixed(1), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ok ? AppColors.ratingGold : color)),
      Text(' / ${needed.toStringAsFixed(1)}', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.55))),
    ]);
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
