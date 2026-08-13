import '../../../core/error/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../data/chef_de_flotte_repository.dart';
import '../widgets/doc_picker_field.dart';
import '../../../core/utils/dem_layout.dart';

class ChefDeFlotteOnboardingScreen extends StatefulWidget {
  const ChefDeFlotteOnboardingScreen({super.key});
  @override
  State<ChefDeFlotteOnboardingScreen> createState() => _State();
}

class _State extends State<ChefDeFlotteOnboardingScreen> {
  final _repo = ChefDeFlotteRepository(ApiClient.dio);

  String? _cniRecto;
  String? _cniVerso;

  final _nameCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _nineaCtrl = TextEditingController();
  final _rccmCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final name = _nameCtrl.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Le nom complet est obligatoire.');
      return;
    }
    if (_cniRecto == null || _cniVerso == null) {
      setState(() => _error = 'CNI recto et verso sont obligatoires.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _repo.submitOnboarding(
        name: name,
        cniRecto: _cniRecto!,
        cniVerso: _cniVerso!,
        companyName: _companyCtrl.text.trim().isEmpty
            ? null
            : _companyCtrl.text.trim(),
        ninea: _nineaCtrl.text.trim().isEmpty ? null : _nineaCtrl.text.trim(),
        rccm: _rccmCtrl.text.trim().isEmpty ? null : _rccmCtrl.text.trim(),
      );
      if (mounted) context.go('/chef-de-flotte/pending');
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _companyCtrl.dispose();
    _nineaCtrl.dispose();
    _rccmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: DemLayout.formMaxWidth(context),
          ),
          child: Column(
            children: [
              // ── Header gradient ──────────────────────────────────────────────
              Container(
                decoration: const BoxDecoration(
                  gradient: AppColors.gradientSplash,
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () => context.go('/role-selection'),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.arrow_back_ios_new,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Builder(
                          builder: (ctx) {
                            final t = MediaQuery.of(ctx).size.width > 600;
                            return Column(
                              children: [
                                Container(
                                  width: t ? 80.0 : 60.0,
                                  height: t ? 80.0 : 60.0,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.handshake_outlined,
                                    color: Colors.white,
                                    size: t ? 40.0 : 30.0,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Devenir Chef de flotte DEM',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: t ? 24.0 : 20.0,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Soumettez votre dossier — validation sous 24–48h',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Formulaire ───────────────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Explication Chef de flotte ──────────────────────────
                      const _CdfExplanation(),
                      const SizedBox(height: 24),

                      // Informations personnelles
                      _SectionTitle(
                        title: 'Informations personnelles',
                        icon: Icons.person_outline,
                      ),
                      const SizedBox(height: 14),
                      _LightField(
                        ctrl: _nameCtrl,
                        label: 'Nom complet *',
                        hint: 'Ex: Mamadou Diallo',
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 24),

                      // Encart info
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.20),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: AppColors.primaryMid,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'En attendant la validation, vous pouvez déjà constituer votre flotte.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primaryMid.withValues(
                                    alpha: 0.85,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Documents obligatoires
                      _SectionTitle(
                        title: 'Documents obligatoires',
                        icon: Icons.badge_outlined,
                      ),
                      const SizedBox(height: 14),
                      DocPickerField(
                        label: 'CNI recto',
                        fieldKey: 'cniRecto',
                        isRequired: true,
                        onChanged: (url) => setState(() => _cniRecto = url),
                      ),
                      const SizedBox(height: 12),
                      DocPickerField(
                        label: 'CNI verso',
                        fieldKey: 'cniVerso',
                        isRequired: true,
                        onChanged: (url) => setState(() => _cniVerso = url),
                      ),
                      const SizedBox(height: 28),

                      // Entreprise (optionnel)
                      _SectionTitle(
                        title: 'Entreprise (optionnel)',
                        icon: Icons.business_outlined,
                        muted: true,
                      ),
                      const SizedBox(height: 14),
                      _LightField(
                        ctrl: _companyCtrl,
                        label: 'Nom entreprise',
                        hint: 'Ex: Transport Diallo SARL',
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),
                      _LightField(
                        ctrl: _nineaCtrl,
                        label: 'NINEA',
                        hint: '000000000 0A0',
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),
                      _LightField(
                        ctrl: _rccmCtrl,
                        label: 'RCCM',
                        hint: 'SN-DKR-XXXX',
                        textInputAction: TextInputAction.done,
                      ),

                      // Erreur
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        _ErrorBanner(message: _error!),
                      ],

                      const SizedBox(height: 28),
                      _GradientButton(
                        label: 'Soumettre le dossier',
                        loading: _loading,
                        onTap: _submit,
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ), // {W}
        ), // ConstrainedBox
      ), // Center
    );
  }
}

// ── Widgets locaux ────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool muted;
  const _SectionTitle({
    required this.title,
    required this.icon,
    this.muted = false,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: muted ? Colors.grey : AppColors.primaryMid, size: 18),
      const SizedBox(width: 8),
      Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: muted ? Colors.grey : AppColors.primaryMid,
        ),
      ),
    ],
  );
}

class _LightField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  const _LightField({
    required this.ctrl,
    required this.label,
    required this.hint,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
  });
  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    textCapitalization: textCapitalization,
    textInputAction: textInputAction,
    style: const TextStyle(color: Color(0xFF1F2937), fontSize: 14),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
      hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF1F5F9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
    child: Row(
      children: [
        Icon(Icons.error_outline, color: Colors.red.shade600, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: Colors.red.shade700, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

class _CdfExplanation extends StatelessWidget {
  const _CdfExplanation();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.handshake_outlined,
                  color: Color(0xFF7C3AED),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'C\'est quoi un Chef de flotte ?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4C1D95),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _CdfPoint(
            icon: Icons.groups_outlined,
            text: 'Recrutez et gérez une équipe de livreurs DEM sous votre nom',
          ),
          const SizedBox(height: 10),
          const _CdfPoint(
            icon: Icons.trending_up_outlined,
            text:
                'Gagnez une commission sur chaque livraison effectuée par votre flotte',
          ),
          const SizedBox(height: 10),
          const _CdfPoint(
            icon: Icons.dashboard_outlined,
            text:
                'Accédez à un tableau de bord dédié : suivi en temps réel, statistiques, performances',
          ),
          const SizedBox(height: 10),
          const _CdfPoint(
            icon: Icons.verified_user_outlined,
            text:
                'Vos livreurs sont rattachés à vous — vous êtes responsable de leur activité',
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.star_outline, color: Color(0xFF7C3AED), size: 15),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Idéal si vous avez déjà un réseau de livreurs ou souhaitez développer votre propre activité de transport.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF5B21B6),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CdfPoint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _CdfPoint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: const Color(0xFF7C3AED), size: 16),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF374151),
            height: 1.4,
          ),
        ),
      ),
    ],
  );
}

class _GradientButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;
  const _GradientButton({
    required this.label,
    required this.onTap,
    this.loading = false,
  });
  @override
  Widget build(BuildContext context) => Container(
    height: DemLayout.isTablet(context) ? 56.0 : 52.0,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [
          AppColors.primary,
          AppColors.primaryMid,
          AppColors.primaryDark,
        ],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.35),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: loading ? null : onTap,
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
        ),
      ),
    ),
  );
}
