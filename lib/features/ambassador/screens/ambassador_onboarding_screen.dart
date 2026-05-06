import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../data/ambassador_repository.dart';

class AmbassadorOnboardingScreen extends StatefulWidget {
  const AmbassadorOnboardingScreen({super.key});
  @override
  State<AmbassadorOnboardingScreen> createState() => _State();
}

class _State extends State<AmbassadorOnboardingScreen> {
  final _repo = AmbassadorRepository(ApiClient.dio);

  final _cniRectoCtrl   = TextEditingController();
  final _cniVersoCtrl   = TextEditingController();
  final _companyCtrl    = TextEditingController();
  final _nineaCtrl      = TextEditingController();
  final _rccmCtrl       = TextEditingController();

  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (_cniRectoCtrl.text.trim().isEmpty || _cniVersoCtrl.text.trim().isEmpty) {
      setState(() => _error = 'CNI recto et verso sont obligatoires.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await _repo.submitOnboarding(
        cniRecto:    _cniRectoCtrl.text.trim(),
        cniVerso:    _cniVersoCtrl.text.trim(),
        companyName: _companyCtrl.text.trim().isEmpty ? null : _companyCtrl.text.trim(),
        ninea:       _nineaCtrl.text.trim().isEmpty   ? null : _nineaCtrl.text.trim(),
        rccm:        _rccmCtrl.text.trim().isEmpty    ? null : _rccmCtrl.text.trim(),
      );
      if (mounted) context.go('/ambassador/pending');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
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
        title: const Text('Devenir Ambassadeur DEM'),
        backgroundColor: const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.2)),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline, color: Color(0xFF7C3AED), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Soumettez votre dossier. L\'admin validera sous 24–48h. En attendant, vous pouvez déjà constituer votre flotte.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF5B21B6)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),

            // Documents obligatoires
            _Section(title: 'Documents obligatoires', icon: Icons.badge_outlined, color: const Color(0xFF7C3AED)),
            const SizedBox(height: 12),
            _Field(ctrl: _cniRectoCtrl, label: 'URL CNI recto *', hint: 'https://...'),
            const SizedBox(height: 10),
            _Field(ctrl: _cniVersoCtrl, label: 'URL CNI verso *', hint: 'https://...'),
            const SizedBox(height: 24),

            // Infos entreprise (optionnel)
            _Section(title: 'Entreprise (optionnel)', icon: Icons.business_outlined, color: Colors.grey),
            const SizedBox(height: 12),
            _Field(ctrl: _companyCtrl, label: 'Nom entreprise', hint: 'Ex: Transport Diallo SARL'),
            const SizedBox(height: 10),
            _Field(ctrl: _nineaCtrl,   label: 'NINEA',           hint: '000000000 0A0'),
            const SizedBox(height: 10),
            _Field(ctrl: _rccmCtrl,    label: 'RCCM',            hint: 'SN-DKR-XXXX'),

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
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Soumettre le dossier', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
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
  final String title;
  final IconData icon;
  final Color color;
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
  final String label;
  final String hint;
  const _Field({required this.ctrl, required this.label, required this.hint});
  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
  );
}
