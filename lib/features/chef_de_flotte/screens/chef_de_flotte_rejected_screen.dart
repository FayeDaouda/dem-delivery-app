import '../../../core/error/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/network_error_widget.dart';
import '../../../features/profile/data/profile_repository.dart';
import '../data/chef_de_flotte_repository.dart';
import '../widgets/doc_picker_field.dart';

class ChefDeFlotteRejectedScreen extends StatefulWidget {
  const ChefDeFlotteRejectedScreen({super.key});
  @override
  State<ChefDeFlotteRejectedScreen> createState() => _State();
}

class _State extends State<ChefDeFlotteRejectedScreen> {
  final _repo        = ChefDeFlotteRepository(ApiClient.dio);
  final _profileRepo = ProfileRepository();

  String? _cniRecto;
  String? _cniVerso;

  final _companyCtrl = TextEditingController();
  final _nineaCtrl   = TextEditingController();
  final _rccmCtrl    = TextEditingController();

  String? _rejectionReason;
  bool    _loadingProfile = true;
  bool    _loadFailed     = false;
  bool    _submitting     = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final user = await _profileRepo.getMe();
      if (!mounted) return;
      setState(() {
        _rejectionReason = user['rejectionReason'] as String?;
        _cniRecto        = user['cniRecto']    as String?;
        _cniVerso        = user['cniVerso']    as String?;
        _companyCtrl.text = user['companyName'] as String? ?? '';
        _nineaCtrl.text   = user['ninea']       as String? ?? '';
        _rccmCtrl.text    = user['rccm']        as String? ?? '';
        _loadingProfile   = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loadingProfile = false; _loadFailed = true; _error = friendlyError(e); });
    }
  }

  Future<void> _submit() async {
    if (_cniRecto == null || _cniVerso == null) {
      setState(() => _error = 'CNI recto et verso sont obligatoires.');
      return;
    }
    setState(() { _submitting = true; _error = null; });
    try {
      await _repo.resubmitOnboarding(
        cniRecto:    _cniRecto!,
        cniVerso:    _cniVerso!,
        companyName: _companyCtrl.text.trim().isEmpty ? null : _companyCtrl.text.trim(),
        ninea:       _nineaCtrl.text.trim().isEmpty   ? null : _nineaCtrl.text.trim(),
        rccm:        _rccmCtrl.text.trim().isEmpty    ? null : _rccmCtrl.text.trim(),
      );
      if (mounted) context.go('/chef-de-flotte/pending');
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    _nineaCtrl.dispose();
    _rccmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _loadingProfile
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _loadFailed
              ? NetworkErrorWidget(
                  message: _error!,
                  onRetry: () { setState(() { _loadingProfile = true; _loadFailed = false; _error = null; }); _loadProfile(); },
                )
              : Column(
              children: [
                // ── Header gradient ──────────────────────────────────────
                Container(
                  decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: Column(children: [
                        Row(children: [
                          GestureDetector(
                            onTap: () => context.pop(),
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
                        const SizedBox(height: 16),
                        Container(
                          width: 60, height: 60,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.edit_document, color: Colors.white, size: 28),
                        ),
                        const SizedBox(height: 12),
                        const Text('Corriger mon dossier',
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text('Modifiez les documents et resoumettez',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12)),
                      ]),
                    ),
                  ),
                ),

                // ── Formulaire ───────────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // Bannière motif refus
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(Icons.cancel_outlined, color: Colors.red.shade600, size: 20),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Dossier refusé',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.red.shade700)),
                              if (_rejectionReason != null) ...[
                                const SizedBox(height: 4),
                                Text('Motif : $_rejectionReason',
                                  style: TextStyle(fontSize: 13, color: Colors.red.shade600, height: 1.4)),
                              ],
                            ])),
                          ]),
                        ),
                        const SizedBox(height: 16),

                        // Encart infos
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.info_outline, color: AppColors.primaryMid, size: 16),
                            const SizedBox(width: 8),
                            const Expanded(child: Text(
                              'Corrigez les documents ci-dessous. Le dossier sera retraité sous 24–48h.',
                              style: TextStyle(fontSize: 12, color: AppColors.primaryMid),
                            )),
                          ]),
                        ),
                        const SizedBox(height: 24),

                        // Documents
                        _SectionTitle(title: 'Documents obligatoires', icon: Icons.badge_outlined),
                        const SizedBox(height: 14),
                        DocPickerField(
                          label: 'CNI recto',
                          fieldKey: 'cniRecto',
                          isRequired: true,
                          initialUrl: _cniRecto,
                          onChanged: (url) => setState(() => _cniRecto = url),
                        ),
                        const SizedBox(height: 12),
                        DocPickerField(
                          label: 'CNI verso',
                          fieldKey: 'cniVerso',
                          isRequired: true,
                          initialUrl: _cniVerso,
                          onChanged: (url) => setState(() => _cniVerso = url),
                        ),
                        const SizedBox(height: 28),

                        // Entreprise
                        _SectionTitle(title: 'Entreprise (optionnel)', icon: Icons.business_outlined, muted: true),
                        const SizedBox(height: 14),
                        _LightField(ctrl: _companyCtrl, label: 'Nom entreprise', hint: 'Ex: Transport Diallo SARL'),
                        const SizedBox(height: 10),
                        _LightField(ctrl: _nineaCtrl,   label: 'NINEA',           hint: '000000000 0A0'),
                        const SizedBox(height: 10),
                        _LightField(ctrl: _rccmCtrl,    label: 'RCCM',            hint: 'SN-DKR-XXXX'),

                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          _ErrorBanner(message: _error!),
                        ],

                        const SizedBox(height: 28),
                        _GradientButton(
                          label: 'Corriger et resoumettre',
                          loading: _submitting,
                          onTap: _submit,
                        ),
                        const SizedBox(height: 24),
                      ],
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
  final String title; final IconData icon; final bool muted;
  const _SectionTitle({required this.title, required this.icon, this.muted = false});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: muted ? Colors.grey : AppColors.primaryMid, size: 18),
    const SizedBox(width: 8),
    Text(title, style: TextStyle(
      fontWeight: FontWeight.w700, fontSize: 14,
      color: muted ? Colors.grey : AppColors.primaryMid,
    )),
  ]);
}

class _LightField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  const _LightField({required this.ctrl, required this.label, required this.hint});
  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    style: const TextStyle(color: Color(0xFF1F2937), fontSize: 14),
    decoration: InputDecoration(
      labelText: label, hintText: hint,
      labelStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
      hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF1F5F9),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
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
    height: 52,
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
