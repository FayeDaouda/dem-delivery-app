import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/api_client.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/router/app_startup_notifier.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dem_layout.dart';
import '../../profile/data/profile_repository.dart';
import '../providers/dem_pro_provider.dart';
import '../theme/dem_pro_colors.dart';

final _emailRegex = RegExp(r'^[\w.\-]+@[\w\-]+\.[\w\-.]+$');

const _sectorLabels = {
  'commerce':     'Commerce',
  'restauration': 'Restauration',
  'services':     'Services',
  'artisanat':    'Artisanat',
  'autre':        'Autre',
};

class _VolumeOption {
  final String value;
  final String title;
  const _VolumeOption(this.value, this.title);
}

const _volumeOptions = [
  _VolumeOption('low',    '1 à 4'),
  _VolumeOption('medium', '5 à 8'),
  _VolumeOption('high',   '9 ou plus'),
];

class DemProOnboardingScreen extends ConsumerStatefulWidget {
  const DemProOnboardingScreen({super.key});
  @override
  ConsumerState<DemProOnboardingScreen> createState() => _State();
}

class _State extends ConsumerState<DemProOnboardingScreen> {
  final _firstNameCtrl    = TextEditingController();
  final _lastNameCtrl     = TextEditingController();
  final _businessNameCtrl = TextEditingController();
  final _emailCtrl        = TextEditingController();

  String? _sector;
  String? _weeklyVolume = 'low';
  XFile?  _pickedAvatar;

  bool    _loadingProfile = true;
  bool    _submitting     = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // Pré-remplit le formulaire (resoumission après refus, ou bascule Client → Pro)
  Future<void> _loadProfile() async {
    try {
      final user = await ProfileRepository().getMe();
      if (!mounted) return;

      final name = (user['name'] as String? ?? '').trim();
      if (name.isNotEmpty) {
        final parts = name.split(RegExp(r'\s+'));
        _firstNameCtrl.text = parts.first;
        if (parts.length > 1) _lastNameCtrl.text = parts.sublist(1).join(' ');
      }
      _businessNameCtrl.text = user['proBusinessName'] as String? ?? '';
      _emailCtrl.text        = user['email'] as String? ?? '';
      _sector       = user['proSector'] as String?;
      _weeklyVolume = user['proWeeklyVolume'] as String?;
    } catch (_) {
      // Non-bloquant : l'utilisateur peut remplir depuis zéro
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final firstName    = _firstNameCtrl.text.trim();
    final lastName     = _lastNameCtrl.text.trim();
    final businessName = _businessNameCtrl.text.trim();
    final email        = _emailCtrl.text.trim();

    if (firstName.length < 2 || lastName.length < 2) {
      setState(() => _error = 'Prénom et nom sont obligatoires (2 caractères min.).');
      return;
    }
    if (businessName.length < 2) {
      setState(() => _error = 'Le nom de l\'entreprise est obligatoire (2 caractères min.).');
      return;
    }
    if (_sector == null) {
      setState(() => _error = 'Sélectionnez le domaine d\'activité.');
      return;
    }
    if (email.isNotEmpty && !_emailRegex.hasMatch(email)) {
      setState(() => _error = 'Adresse e-mail invalide.');
      return;
    }
    if (_weeklyVolume == null) {
      setState(() => _error = 'Indiquez votre volume de livraisons par semaine.');
      return;
    }

    setState(() { _submitting = true; _error = null; });
    try {
      await ref.read(demProProvider.notifier).submitOnboarding(
        firstName:    firstName,
        lastName:     lastName,
        businessName: businessName,
        sector:       _sector!,
        email:        email.isEmpty ? null : email,
        weeklyVolume: _weeklyVolume!,
      );
      if (_pickedAvatar != null) {
        try {
          final formData = FormData.fromMap({
            'file': await MultipartFile.fromFile(_pickedAvatar!.path, filename: _pickedAvatar!.name),
            'field': 'avatar',
          });
          await ApiClient.dio.post('/users/driver/documents', data: formData);
        } catch (_) {}
      }
      NotificationService.requestPermissionAndToken();
      appStartupNotifier.markLoggedIn(userRole: 'DEM_PRO', pro: 'PENDING', proDone: true);
      if (mounted) context.go('/dem-pro/pending');
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _businessNameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  // Header pleine largeur — intentionnellement hors du ConstrainedBox du formulaire
  Widget _buildHeader() {
    final isTablet = DemLayout.isTablet(context);
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                GestureDetector(
                  onTap: () => context.go('/role-selection'),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () async {
                  final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, imageQuality: 80);
                  if (picked != null) setState(() => _pickedAvatar = picked);
                },
                child: Stack(
                  children: [
                    Container(
                      width: isTablet ? 80.0 : 72.0,
                      height: isTablet ? 80.0 : 72.0,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.5),
                        image: _pickedAvatar != null
                            ? DecorationImage(image: FileImage(File(_pickedAvatar!.path)), fit: BoxFit.cover)
                            : null,
                      ),
                      child: _pickedAvatar == null
                          ? Icon(Icons.storefront_outlined, color: Colors.white, size: isTablet ? 36.0 : 30.0)
                          : null,
                    ),
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                          color: DemProColors.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Profil de votre entreprise',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isTablet ? 24.0 : 20.0,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ces informations seront examinées par notre équipe',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Header bord-à-bord — jamais contraint par le formMaxWidth
          _buildHeader(),

          if (_loadingProfile)
            const Expanded(
              child: Center(child: CircularProgressIndicator(color: DemProColors.accent)),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: DemLayout.formMaxWidth(context)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [

                          _SectionTitle(title: 'Informations personnelles', icon: Icons.person_outline),
                          const SizedBox(height: 14),
                          _LightField(
                            ctrl: _firstNameCtrl,
                            label: 'Prénom *',
                            hint: 'Ex: Awa',
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),
                          _LightField(
                            ctrl: _lastNameCtrl,
                            label: 'Nom *',
                            hint: 'Ex: Ndiaye',
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 28),

                          _SectionTitle(title: 'Entreprise', icon: Icons.business_outlined),
                          const SizedBox(height: 14),
                          _LightField(
                            ctrl: _businessNameCtrl,
                            label: 'Nom de l\'entreprise *',
                            hint: 'Ex: Boutique Awa',
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),
                          _SectorDropdown(
                            value: _sector,
                            onChanged: (v) => setState(() => _sector = v),
                          ),
                          const SizedBox(height: 12),
                          _LightField(
                            ctrl: _emailCtrl,
                            label: 'Email (optionnel)',
                            hint: 'contact@entreprise.com',
                            keyboard: TextInputType.emailAddress,
                            textInputAction: TextInputAction.done,
                            suffixIcon: const Icon(Icons.mail_outline, color: Color(0xFF9CA3AF), size: 18),
                          ),
                          const SizedBox(height: 28),

                          _SectionTitle(title: 'Activité', icon: Icons.two_wheeler),
                          const SizedBox(height: 8),
                          const Text(
                            'Combien de livraisons effectuez-vous par semaine ?',
                            style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              for (int i = 0; i < _volumeOptions.length; i++) ...[
                                if (i > 0) const SizedBox(width: 10),
                                Expanded(
                                  child: _VolumeCard(
                                    option: _volumeOptions[i],
                                    selected: _weeklyVolume == _volumeOptions[i].value,
                                    onTap: () => setState(() => _weeklyVolume = _volumeOptions[i].value),
                                  ),
                                ),
                              ],
                            ],
                          ),

                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            _ErrorBanner(message: _error!),
                          ],

                          const SizedBox(height: 32),
                          _GradientButton(
                            label: 'Envoyer ma demande',
                            loading: _submitting,
                            onTap: _submit,
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Widgets locaux ────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionTitle({required this.title, required this.icon});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: AppColors.primaryMid, size: 18),
    const SizedBox(width: 8),
    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.primaryMid)),
  ]);
}

class _LightField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String hint;
  final TextCapitalization textCapitalization;
  final TextInputType keyboard;
  final Widget? suffixIcon;
  final TextInputAction? textInputAction;
  const _LightField({
    required this.ctrl, required this.label, required this.hint,
    this.textCapitalization = TextCapitalization.none,
    this.keyboard = TextInputType.text,
    this.suffixIcon,
    this.textInputAction,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF374151),
        ),
      ),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        textCapitalization: textCapitalization,
        keyboardType: keyboard,
        textInputAction: textInputAction,
        style: const TextStyle(color: Color(0xFF1F2937), fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: const Color(0xFFF1F5F9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: DemProColors.accent, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    ],
  );
}

class _SectorDropdown extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _SectorDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Domaine d\'activité *',
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF374151),
        ),
      ),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        initialValue: value,
        onChanged: onChanged,
        hint: const Text(
          'Sélectionner un domaine',
          style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
        ),
        icon: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: DemProColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(Icons.keyboard_arrow_down_rounded, color: DemProColors.accent, size: 18),
        ),
        style: const TextStyle(color: Color(0xFF1F2937), fontSize: 14),
        dropdownColor: Colors.white,
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFFF1F5F9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: DemProColors.accent, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        items: _sectorLabels.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
      ),
    ],
  );
}

class _VolumeCard extends StatelessWidget {
  final _VolumeOption option;
  final bool selected;
  final VoidCallback onTap;
  const _VolumeCard({required this.option, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeInOut,
    decoration: BoxDecoration(
      color: selected ? DemProColors.accent : const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: selected ? DemProColors.accent : const Color(0xFFE5E7EB),
        width: selected ? 2 : 1,
      ),
      boxShadow: selected
          ? [BoxShadow(color: DemProColors.accent.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))]
          : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4, offset: const Offset(0, 2))],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        splashColor: DemProColors.accent.withValues(alpha: 0.15),
        highlightColor: DemProColors.accent.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : const Color(0xFF1F2937),
                ),
                child: Text(option.title, textAlign: TextAlign.center),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 10, height: 1.2,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.85)
                      : const Color(0xFF6B7280),
                ),
                child: const Text('livraisons /\nsemaine', textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.red.shade200),
    ),
    child: Row(children: [
      Icon(Icons.error_outline, color: Colors.red.shade600, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(message, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
    ]),
  );
}

class _GradientButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;
  const _GradientButton({required this.label, required this.onTap, this.loading = false});
  @override
  Widget build(BuildContext context) => Container(
    height: DemLayout.isTablet(context) ? 56.0 : 52.0,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [AppColors.primary, AppColors.primaryMid, AppColors.primaryDark],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: loading ? null : onTap,
        child: Center(
          child: loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      ),
    ),
  );
}
