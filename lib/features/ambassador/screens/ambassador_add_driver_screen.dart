import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/api/api_client.dart';
import '../data/ambassador_repository.dart';

const _purple  = Color(0xFF7C3AED);
const _purple2 = Color(0xFF5B21B6);

// ── Phone formatter : "77 123 45 67" ──────────────────────────────────────────
class _PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits  = newValue.text.replaceAll(RegExp(r'\D'), '');
    final capped  = digits.length > 9 ? digits.substring(0, 9) : digits;
    final buf     = StringBuffer();
    for (int i = 0; i < capped.length; i++) {
      if (i == 2 || i == 5 || i == 7) buf.write(' ');
      buf.write(capped[i]);
    }
    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class AmbassadorAddDriverScreen extends StatefulWidget {
  const AmbassadorAddDriverScreen({super.key});
  @override
  State<AmbassadorAddDriverScreen> createState() => _State();
}

class _State extends State<AmbassadorAddDriverScreen> {
  final _repo = AmbassadorRepository(ApiClient.dio);

  final _nameCtrl          = TextEditingController();
  final _phoneCtrl         = TextEditingController();
  final _licenseFrontCtrl  = TextEditingController();
  final _licenseBackCtrl   = TextEditingController();
  final _vehiclePhotoCtrl  = TextEditingController();
  final _carteGriseCtrl    = TextEditingController();
  final _assuranceCtrl     = TextEditingController();
  final _casqueCtrl        = TextEditingController();

  DateTime? _insuranceExpiry;
  bool      _loading = false;
  String?   _error;

  int get _digitCount => _phoneCtrl.text.replaceAll(' ', '').length;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _licenseFrontCtrl.dispose();
    _licenseBackCtrl.dispose();
    _vehiclePhotoCtrl.dispose();
    _carteGriseCtrl.dispose();
    _assuranceCtrl.dispose();
    _casqueCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _insuranceExpiry ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _purple),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _insuranceExpiry = picked);
  }

  Future<void> _submit() async {
    final name  = _nameCtrl.text.trim();
    final phone = '+221${_phoneCtrl.text.replaceAll(' ', '').trim()}';

    if (name.isEmpty) {
      setState(() => _error = 'Le nom du livreur est obligatoire.');
      return;
    }
    if (_digitCount < 8) {
      setState(() => _error = 'Numéro de téléphone invalide.');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      await _repo.createDriver(
        phone:           phone,
        name:            name,
        vehicleType:     'MOTO',
        licenseFront:    _licenseFrontCtrl.text.trim().isEmpty  ? null : _licenseFrontCtrl.text.trim(),
        licenseBack:     _licenseBackCtrl.text.trim().isEmpty   ? null : _licenseBackCtrl.text.trim(),
        vehiclePhoto:    _vehiclePhotoCtrl.text.trim().isEmpty  ? null : _vehiclePhotoCtrl.text.trim(),
        carteGrise:      _carteGriseCtrl.text.trim().isEmpty    ? null : _carteGriseCtrl.text.trim(),
        assurance:       _assuranceCtrl.text.trim().isEmpty     ? null : _assuranceCtrl.text.trim(),
        insuranceExpiry: _insuranceExpiry?.toIso8601String(),
        casquePhoto:     _casqueCtrl.text.trim().isEmpty        ? null : _casqueCtrl.text.trim(),
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
      body: Column(
        children: [
          // ── Header gradient ──────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_purple, _purple2], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ajouter un livreur',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                          SizedBox(height: 2),
                          Text('Renseignez les informations du livreur',
                            style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
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

                  // ── Infos de base ──
                  _SectionTitle(title: 'Informations de base', icon: Icons.person_outline, color: _purple),
                  const SizedBox(height: 12),

                  _UrlField(ctrl: _nameCtrl, label: 'Nom complet *',
                    hint: 'Ex : Mamadou Diallo',
                    icon: Icons.badge_outlined,
                    textCapitalization: TextCapitalization.words),
                  const SizedBox(height: 10),

                  // Téléphone avec préfixe +221
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Label('Téléphone *'),
                      const SizedBox(height: 6),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey.shade50,
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
                            decoration: InputDecoration(
                              hintText: '77 123 45 67',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            ),
                          ),
                        ),
                      ]),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ── Documents du permis ──
                  _SectionTitle(title: 'Permis de conduire', icon: Icons.article_outlined, color: Colors.blueGrey),
                  const SizedBox(height: 12),
                  _UrlField(ctrl: _licenseFrontCtrl, label: 'URL Permis recto', hint: 'https://...', icon: Icons.image_outlined),
                  const SizedBox(height: 10),
                  _UrlField(ctrl: _licenseBackCtrl,  label: 'URL Permis verso', hint: 'https://...', icon: Icons.image_outlined),

                  const SizedBox(height: 24),

                  // ── Documents du véhicule ──
                  _SectionTitle(title: 'Véhicule & Assurance', icon: Icons.motorcycle, color: Colors.blueGrey),
                  const SizedBox(height: 12),
                  _UrlField(ctrl: _vehiclePhotoCtrl, label: 'URL Photo moto (plaque visible)', hint: 'https://...', icon: Icons.photo_camera_outlined),
                  const SizedBox(height: 10),
                  _UrlField(ctrl: _carteGriseCtrl,   label: 'URL Carte grise', hint: 'https://...', icon: Icons.description_outlined),
                  const SizedBox(height: 10),
                  _UrlField(ctrl: _assuranceCtrl,    label: "URL Attestation d'assurance", hint: 'https://...', icon: Icons.security_outlined),
                  const SizedBox(height: 10),

                  // Date expiration assurance
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Label("Expiration de l'assurance"),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: _pickDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(children: [
                            Icon(Icons.calendar_today_outlined, size: 18, color: _insuranceExpiry != null ? _purple : Colors.grey),
                            const SizedBox(width: 10),
                            Text(
                              _insuranceExpiry != null
                                ? '${_insuranceExpiry!.day.toString().padLeft(2,'0')}/${_insuranceExpiry!.month.toString().padLeft(2,'0')}/${_insuranceExpiry!.year}'
                                : 'Sélectionner une date',
                              style: TextStyle(
                                fontSize: 14,
                                color: _insuranceExpiry != null ? const Color(0xFF1F2937) : Colors.grey,
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ── Équipement ──
                  _SectionTitle(title: 'Équipement', icon: Icons.sports_motorsports_outlined, color: Colors.blueGrey),
                  const SizedBox(height: 12),
                  _UrlField(ctrl: _casqueCtrl, label: 'URL Photo casque', hint: 'https://...', icon: Icons.photo_camera_outlined),

                  // ── Erreur ──
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(children: [
                        Icon(Icons.error_outline, color: Colors.red.shade600, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13))),
                      ]),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // ── Bouton ──
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _purple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: _loading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Ajouter le livreur', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ),

                  const SizedBox(height: 12),
                  const Center(
                    child: Text(
                      'Le livreur sera validé par l\'admin avant activation.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 12),
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
  final String  title;
  final IconData icon;
  final Color   color;
  const _SectionTitle({required this.title, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: color, size: 18),
    const SizedBox(width: 8),
    Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: color)),
  ]);
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
  );
}

class _UrlField extends StatelessWidget {
  final TextEditingController ctrl;
  final String  label;
  final String  hint;
  final IconData icon;
  final TextCapitalization textCapitalization;
  const _UrlField({
    required this.ctrl,
    required this.label,
    required this.hint,
    required this.icon,
    this.textCapitalization = TextCapitalization.none,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Label(label),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        keyboardType: TextInputType.url,
        textCapitalization: textCapitalization,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, size: 18, color: Colors.grey),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    ],
  );
}
