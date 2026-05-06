import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../features/profile/data/profile_repository.dart';
import '../data/ambassador_repository.dart';

const _purple = Color(0xFF7C3AED);

class AmbassadorRejectedScreen extends StatefulWidget {
  const AmbassadorRejectedScreen({super.key});
  @override
  State<AmbassadorRejectedScreen> createState() => _State();
}

class _State extends State<AmbassadorRejectedScreen> {
  final _repo        = AmbassadorRepository(ApiClient.dio);
  final _profileRepo = ProfileRepository();

  final _cniRectoCtrl  = TextEditingController();
  final _cniVersoCtrl  = TextEditingController();
  final _companyCtrl   = TextEditingController();
  final _nineaCtrl     = TextEditingController();
  final _rccmCtrl      = TextEditingController();

  String? _rejectionReason;
  bool    _loadingProfile = true;
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
        _cniRectoCtrl.text = user['cniRecto']     as String? ?? '';
        _cniVersoCtrl.text = user['cniVerso']     as String? ?? '';
        _companyCtrl.text  = user['companyName']  as String? ?? '';
        _nineaCtrl.text    = user['ninea']         as String? ?? '';
        _rccmCtrl.text     = user['rccm']          as String? ?? '';
        _loadingProfile = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  Future<void> _submit() async {
    if (_cniRectoCtrl.text.trim().isEmpty || _cniVersoCtrl.text.trim().isEmpty) {
      setState(() => _error = 'CNI recto et verso sont obligatoires.');
      return;
    }
    setState(() { _submitting = true; _error = null; });
    try {
      await _repo.resubmitOnboarding(
        cniRecto:    _cniRectoCtrl.text.trim(),
        cniVerso:    _cniVersoCtrl.text.trim(),
        companyName: _companyCtrl.text.trim().isEmpty ? null : _companyCtrl.text.trim(),
        ninea:       _nineaCtrl.text.trim().isEmpty   ? null : _nineaCtrl.text.trim(),
        rccm:        _rccmCtrl.text.trim().isEmpty    ? null : _rccmCtrl.text.trim(),
      );
      if (mounted) context.go('/ambassador/pending');
    } catch (e) {
      final msg = e.toString();
      setState(() => _error = msg.contains('Exception:') ? msg.replaceFirst('Exception: ', '') : msg);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _cniRectoCtrl.dispose(); _cniVersoCtrl.dispose();
    _companyCtrl.dispose();  _nineaCtrl.dispose(); _rccmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Corriger mon dossier'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: _loadingProfile
          ? const Center(child: CircularProgressIndicator(color: _purple))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── Bannière refus ──────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.cancel_outlined, color: Colors.red.shade600, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Dossier refusé',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.red.shade700)),
                          if (_rejectionReason != null) ...[
                            const SizedBox(height: 6),
                            Text('Motif : $_rejectionReason',
                              style: TextStyle(fontSize: 13, color: Colors.red.shade600, height: 1.4)),
                          ],
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 20),

                  // ── Info resoumission ────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _purple.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _purple.withValues(alpha: 0.18)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline, color: _purple, size: 18),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Corrigez les documents ci-dessous et resoumettez. L\'équipe DEM retraitera votre dossier sous 24–48h.',
                          style: TextStyle(fontSize: 13, color: _purple),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 24),

                  // ── Documents obligatoires ───────────────────────────────
                  _Section(title: 'Documents obligatoires', icon: Icons.badge_outlined, color: _purple),
                  const SizedBox(height: 12),
                  _Field(ctrl: _cniRectoCtrl, label: 'URL CNI recto *', hint: 'https://...'),
                  const SizedBox(height: 10),
                  _Field(ctrl: _cniVersoCtrl, label: 'URL CNI verso *', hint: 'https://...'),
                  const SizedBox(height: 24),

                  // ── Entreprise ───────────────────────────────────────────
                  _Section(title: 'Entreprise (optionnel)', icon: Icons.business_outlined, color: Colors.grey),
                  const SizedBox(height: 12),
                  _Field(ctrl: _companyCtrl, label: 'Nom entreprise', hint: 'Ex: Transport Diallo SARL'),
                  const SizedBox(height: 10),
                  _Field(ctrl: _nineaCtrl,   label: 'NINEA',           hint: '000000000 0A0'),
                  const SizedBox(height: 10),
                  _Field(ctrl: _rccmCtrl,    label: 'RCCM',            hint: 'SN-DKR-XXXX'),

                  // ── Erreur ───────────────────────────────────────────────
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
                    ),
                  ],

                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _purple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: _submitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Corriger et resoumettre', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title; final IconData icon; final Color color;
  const _Section({required this.title, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: color, size: 18),
    const SizedBox(width: 8),
    Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: color)),
  ]);
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  const _Field({required this.ctrl, required this.label, required this.hint});
  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    decoration: InputDecoration(
      labelText: label, hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
  );
}
