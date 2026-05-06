import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../data/ambassador_repository.dart';
import '../widgets/doc_picker_field.dart';

class _PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits  = newValue.text.replaceAll(RegExp(r'\D'), '');
    final capped  = digits.length > 9 ? digits.substring(0, 9) : digits;
    final buf     = StringBuffer();
    for (int i = 0; i < capped.length; i++) {
      if (i == 2 || i == 5 || i == 7) buf.write(' ');
      buf.write(capped[i]);
    }
    final formatted = buf.toString();
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}

class AmbassadorAddDriverScreen extends StatefulWidget {
  const AmbassadorAddDriverScreen({super.key});
  @override
  State<AmbassadorAddDriverScreen> createState() => _State();
}

class _State extends State<AmbassadorAddDriverScreen> {
  final _repo     = AmbassadorRepository(ApiClient.dio);
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  String?   _licenseFront;
  String?   _licenseBack;
  String?   _vehiclePhoto;
  String?   _carteGrise;
  String?   _assurance;
  String?   _casquePhoto;
  DateTime? _insuranceExpiry;

  bool    _loading = false;
  String? _error;

  int get _digitCount => _phoneCtrl.text.replaceAll(' ', '').length;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _insuranceExpiry ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _insuranceExpiry = picked);
  }

  Future<void> _submit() async {
    final name  = _nameCtrl.text.trim();
    final phone = '+221${_phoneCtrl.text.replaceAll(' ', '').trim()}';

    if (name.isEmpty) { setState(() => _error = 'Le nom est obligatoire.'); return; }
    if (_digitCount < 8) { setState(() => _error = 'Numéro invalide.'); return; }

    setState(() { _loading = true; _error = null; });
    try {
      await _repo.createDriver(
        phone:           phone,
        name:            name,
        vehicleType:     'MOTO',
        licenseFront:    _licenseFront,
        licenseBack:     _licenseBack,
        vehiclePhoto:    _vehiclePhoto,
        carteGrise:      _carteGrise,
        assurance:       _assurance,
        insuranceExpiry: _insuranceExpiry?.toIso8601String(),
        casquePhoto:     _casquePhoto,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      final msg = e.toString();
      setState(() => _error = msg.contains('Exception:') ? msg.replaceFirst('Exception: ', '') : msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // ── Header gradient ──────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Ajouter un livreur',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                      SizedBox(height: 2),
                      Text('Renseignez les informations du livreur',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),

          // ── Formulaire ───────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  _SectionTitle(title: 'Informations de base', icon: Icons.person_outline),
                  const SizedBox(height: 14),

                  _LightField(ctrl: _nameCtrl, label: 'Nom complet *', hint: 'Ex : Mamadou Diallo',
                    textCapitalization: TextCapitalization.words),
                  const SizedBox(height: 10),

                  // Téléphone
                  const _FieldLabel('Téléphone *'),
                  const SizedBox(height: 6),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('+221', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [_PhoneFormatter()],
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(color: Color(0xFF1F2937), fontSize: 14),
                        decoration: InputDecoration(
                          hintText: '77 123 45 67',
                          hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: AppColors.primary, width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 28),

                  _SectionTitle(title: 'Permis de conduire', icon: Icons.article_outlined, muted: true),
                  const SizedBox(height: 14),
                  DocPickerField(label: 'Permis recto', fieldKey: 'licenseFront', onChanged: (u) => setState(() => _licenseFront = u)),
                  const SizedBox(height: 12),
                  DocPickerField(label: 'Permis verso',  fieldKey: 'licenseBack',  onChanged: (u) => setState(() => _licenseBack  = u)),
                  const SizedBox(height: 28),

                  _SectionTitle(title: 'Véhicule & Assurance', icon: Icons.motorcycle, muted: true),
                  const SizedBox(height: 14),
                  DocPickerField(label: 'Photo moto (plaque visible)', fieldKey: 'vehiclePhoto', onChanged: (u) => setState(() => _vehiclePhoto = u)),
                  const SizedBox(height: 12),
                  DocPickerField(label: 'Carte grise',               fieldKey: 'carteGrise',   onChanged: (u) => setState(() => _carteGrise   = u)),
                  const SizedBox(height: 12),
                  DocPickerField(label: "Attestation d'assurance",   fieldKey: 'assurance',     onChanged: (u) => setState(() => _assurance    = u)),
                  const SizedBox(height: 12),

                  // Date expiration
                  const _FieldLabel("Expiration de l'assurance"),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(children: [
                        Icon(Icons.calendar_today_outlined, size: 18,
                          color: _insuranceExpiry != null ? AppColors.primary : const Color(0xFF9CA3AF)),
                        const SizedBox(width: 10),
                        Text(
                          _insuranceExpiry != null
                            ? '${_insuranceExpiry!.day.toString().padLeft(2,'0')}/${_insuranceExpiry!.month.toString().padLeft(2,'0')}/${_insuranceExpiry!.year}'
                            : 'Sélectionner une date',
                          style: TextStyle(
                            fontSize: 14,
                            color: _insuranceExpiry != null ? const Color(0xFF1F2937) : const Color(0xFF9CA3AF),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 28),

                  _SectionTitle(title: 'Équipement', icon: Icons.sports_motorsports_outlined, muted: true),
                  const SizedBox(height: 14),
                  DocPickerField(label: 'Photo casque', fieldKey: 'casquePhoto', onChanged: (u) => setState(() => _casquePhoto = u)),

                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _ErrorBanner(message: _error!),
                  ],

                  const SizedBox(height: 28),
                  _GradientButton(label: 'Ajouter le livreur', loading: _loading, onTap: _submit),
                  const SizedBox(height: 12),
                  const Center(
                    child: Text(
                      'Le livreur sera validé par l\'admin avant activation.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Widgets utilitaires ───────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title; final IconData icon; final bool muted;
  const _SectionTitle({required this.title, required this.icon, this.muted = false});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: muted ? Colors.grey.shade500 : AppColors.primaryMid, size: 18),
    const SizedBox(width: 8),
    Text(title, style: TextStyle(
      fontWeight: FontWeight.w700, fontSize: 14,
      color: muted ? Colors.grey.shade600 : AppColors.primaryMid,
    )),
  ]);
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)));
}

class _LightField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final TextCapitalization textCapitalization;
  const _LightField({required this.ctrl, required this.label, required this.hint,
    this.textCapitalization = TextCapitalization.none});
  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    textCapitalization: textCapitalization,
    style: const TextStyle(color: Color(0xFF1F2937), fontSize: 14),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
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
