import '../../../core/error/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/input_formatters.dart';
import '../data/chef_de_flotte_repository.dart';
import '../widgets/doc_picker_field.dart';
import '../../../core/utils/dem_layout.dart';

class _PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue nv) {
    final digits = nv.text.replaceAll(RegExp(r'\D'), '');
    final capped = digits.length > 9 ? digits.substring(0, 9) : digits;
    final buf = StringBuffer();
    for (int i = 0; i < capped.length; i++) {
      if (i == 2 || i == 5 || i == 7) buf.write(' ');
      buf.write(capped[i]);
    }
    final f = buf.toString();
    return TextEditingValue(
      text: f,
      selection: TextSelection.collapsed(offset: f.length),
    );
  }
}

class ChefDeFlotteAddDriverScreen extends StatefulWidget {
  const ChefDeFlotteAddDriverScreen({super.key});
  @override
  State<ChefDeFlotteAddDriverScreen> createState() => _State();
}

class _State extends State<ChefDeFlotteAddDriverScreen> {
  final _repo = ChefDeFlotteRepository(ApiClient.dio);
  final _pageCtrl = PageController();
  int _step = 0;
  static const _total = 3;

  // Step 1
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String? _nameError;

  // Step 2 – docs
  String? _licenseFront, _licenseBack;
  String? _vehiclePhoto, _carteGrise, _assurance, _casquePhoto;
  DateTime? _insuranceExpiry;

  bool _loading = false;
  String? _error;

  int get _digitCount => _phoneCtrl.text.replaceAll(' ', '').length;

  // Récap
  int get _docsUploaded => [
    _licenseFront,
    _licenseBack,
    _vehiclePhoto,
    _carteGrise,
    _assurance,
    _casquePhoto,
  ].where((x) => x != null).length;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() => setState(() {}));
    _phoneCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _goTo(int step) {
    setState(() {
      _step = step;
      _error = null;
    });
    _pageCtrl.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  bool _validateStep1() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _digitCount < 8) {
      setState(() => _nameError = name.isEmpty ? 'Nom obligatoire' : null);
      return false;
    }
    setState(() => _nameError = null);
    return true;
  }

  void _next() {
    if (_step == 0 && !_validateStep1()) return;
    _goTo(_step + 1);
  }

  void _prev() => _goTo(_step - 1);

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _repo.createDriver(
        phone: '+221${_phoneCtrl.text.replaceAll(' ', '').trim()}',
        name: _nameCtrl.text.trim(),
        vehicleType: 'MOTO',
        licenseFront: _licenseFront,
        licenseBack: _licenseBack,
        vehiclePhoto: _vehiclePhoto,
        carteGrise: _carteGrise,
        assurance: _assurance,
        insuranceExpiry: _insuranceExpiry?.toIso8601String(),
        casquePhoto: _casquePhoto,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _insuranceExpiry ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _insuranceExpiry = picked);
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

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
              // ── Header gradient ────────────────────────────────────────────
              Container(
                decoration: const BoxDecoration(
                  gradient: AppColors.gradientSplash,
                ),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back_ios_new,
                                color: Colors.white,
                                size: 18,
                              ),
                              onPressed: () => _step > 0
                                  ? _prev()
                                  : Navigator.of(context).pop(),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Ajouter un livreur',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    _stepSubtitle,
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.75,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${_step + 1}/$_total',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.70),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _StepBar(current: _step, total: _total),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

              // ── Contenu par étape ──────────────────────────────────────────
              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _Step1(
                      nameCtrl: _nameCtrl,
                      phoneCtrl: _phoneCtrl,
                      nameError: _nameError,
                      digitCount: _digitCount,
                    ),
                    _Step2(
                      onLicenseFront: (u) => setState(() => _licenseFront = u),
                      onLicenseBack: (u) => setState(() => _licenseBack = u),
                      onVehiclePhoto: (u) => setState(() => _vehiclePhoto = u),
                      onCarteGrise: (u) => setState(() => _carteGrise = u),
                      onAssurance: (u) => setState(() => _assurance = u),
                      onCasquePhoto: (u) => setState(() => _casquePhoto = u),
                      insuranceExpiry: _insuranceExpiry,
                      onPickDate: _pickDate,
                    ),
                    _Step3(
                      name: _nameCtrl.text.trim(),
                      phone: '+221 ${_phoneCtrl.text.trim()}',
                      docsUploaded: _docsUploaded,
                      docsTotal: 6,
                      docs: {
                        'Permis recto': _licenseFront,
                        'Permis verso': _licenseBack,
                        'Photo moto': _vehiclePhoto,
                        'Carte grise': _carteGrise,
                        'Assurance': _assurance,
                        'Casque': _casquePhoto,
                      },
                      insuranceExpiry: _insuranceExpiry,
                      error: _error,
                    ),
                  ],
                ),
              ),

              // ── Navigation ─────────────────────────────────────────────────
              _NavBar(
                step: _step,
                total: _total,
                loading: _loading,
                canNext: _step == 0
                    ? _nameCtrl.text.trim().isNotEmpty && _digitCount >= 8
                    : true,
                onNext: _step < _total - 1 ? _next : _submit,
                onPrev: _step > 0 ? _prev : null,
                nextLabel: _step == _total - 1
                    ? 'Ajouter le livreur'
                    : 'Suivant',
              ),
            ],
          ), // Column
        ), // ConstrainedBox
      ), // Center
    );
  }

  String get _stepSubtitle => [
    'Informations du livreur',
    'Documents & véhicule',
    'Vérification',
  ][_step];
}

// ── Barre d'étapes ────────────────────────────────────────────────────────────
class _StepBar extends StatelessWidget {
  final int current, total;
  const _StepBar({required this.current, required this.total});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(
      children: [
        // Barre de progression
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (current + 1) / total,
            minHeight: 4,
            backgroundColor: Colors.white.withValues(alpha: 0.25),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
        const SizedBox(height: 10),
        // Labels des étapes
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            total,
            (i) => _StepDot(
              index: i,
              current: current,
              label: ['Infos', 'Documents', 'Vérif.'][i],
            ),
          ),
        ),
      ],
    ),
  );
}

class _StepDot extends StatelessWidget {
  final int index, current;
  final String label;
  const _StepDot({
    required this.index,
    required this.current,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final done = index < current;
    final active = index == current;
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done || active
                ? Colors.white
                : Colors.white.withValues(alpha: 0.25),
            border: active ? Border.all(color: Colors.white, width: 2) : null,
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check, size: 13, color: AppColors.primaryMid)
                : Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: active
                          ? AppColors.primaryDark
                          : Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

// ── Barre de navigation ───────────────────────────────────────────────────────
class _NavBar extends StatelessWidget {
  final int step, total;
  final bool loading, canNext;
  final String nextLabel;
  final VoidCallback onNext;
  final VoidCallback? onPrev;
  const _NavBar({
    required this.step,
    required this.total,
    required this.loading,
    required this.canNext,
    required this.nextLabel,
    required this.onNext,
    this.onPrev,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      16,
      12,
      16,
      MediaQuery.paddingOf(context).bottom + 12,
    ),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Colors.grey.shade100)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, -2),
        ),
      ],
    ),
    child: Row(
      children: [
        if (onPrev != null)
          Expanded(
            flex: 2,
            child: OutlinedButton(
              onPressed: onPrev,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryMid,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                minimumSize: const Size(0, 52),
              ),
              child: const Text(
                'Précédent',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        if (onPrev != null) const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 52,
            decoration: BoxDecoration(
              gradient: canNext
                  ? const LinearGradient(
                      colors: [
                        AppColors.primary,
                        AppColors.primaryMid,
                        AppColors.primaryDark,
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : null,
              color: canNext ? null : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(14),
              boxShadow: canNext
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: canNext && !loading ? onNext : null,
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
                          nextLabel,
                          style: TextStyle(
                            color: canNext
                                ? Colors.white
                                : Colors.grey.shade400,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
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

// ── Étape 1 : Infos ───────────────────────────────────────────────────────────
class _Step1 extends StatelessWidget {
  final TextEditingController nameCtrl, phoneCtrl;
  final String? nameError;
  final int digitCount;
  const _Step1({
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.nameError,
    required this.digitCount,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepHeading(
          icon: Icons.person_outline,
          title: 'Qui est ce livreur ?',
          subtitle: 'Nom complet et numéro de téléphone',
        ),
        const SizedBox(height: 24),

        const _FieldLabel('Nom complet *'),
        const SizedBox(height: 6),
        TextField(
          controller: nameCtrl,
          textCapitalization: TextCapitalization.words,
          inputFormatters: [NameInputFormatter()],
          style: const TextStyle(color: Color(0xFF1F2937), fontSize: 15),
          decoration: _inputDec(
            'Ex : Mamadou Diallo',
            Icons.badge_outlined,
            error: nameError,
          ),
        ),
        const SizedBox(height: 16),

        const _FieldLabel('Téléphone *'),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '+221',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFF374151),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [_PhoneFormatter()],
                style: const TextStyle(color: Color(0xFF1F2937), fontSize: 15),
                decoration: _inputDec('77 123 45 67', Icons.phone_outlined),
              ),
            ),
          ],
        ),
        if (digitCount > 0 && digitCount < 8)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Numéro incomplet (${9 - digitCount} chiffre(s) manquant(s))',
              style: TextStyle(color: Colors.orange.shade700, fontSize: 12),
            ),
          ),
      ],
    ),
  );
}

// ── Étape 2 : Documents ───────────────────────────────────────────────────────
class _Step2 extends StatelessWidget {
  final void Function(String?) onLicenseFront,
      onLicenseBack,
      onVehiclePhoto,
      onCarteGrise,
      onAssurance,
      onCasquePhoto;
  final DateTime? insuranceExpiry;
  final VoidCallback onPickDate;
  const _Step2({
    required this.onLicenseFront,
    required this.onLicenseBack,
    required this.onVehiclePhoto,
    required this.onCarteGrise,
    required this.onAssurance,
    required this.onCasquePhoto,
    required this.insuranceExpiry,
    required this.onPickDate,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Permis
        _DocSection(
          icon: Icons.article_outlined,
          title: 'Permis de conduire',
          color: AppColors.primaryMid,
          children: [
            DocPickerField(
              label: 'Permis recto',
              fieldKey: 'licenseFront',
              onChanged: onLicenseFront,
            ),
            const SizedBox(height: 10),
            DocPickerField(
              label: 'Permis verso',
              fieldKey: 'licenseBack',
              onChanged: onLicenseBack,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Véhicule & assurance
        _DocSection(
          icon: Icons.motorcycle,
          title: 'Véhicule & Assurance',
          color: const Color(0xFF0891B2),
          children: [
            DocPickerField(
              label: 'Photo moto (plaque visible)',
              fieldKey: 'vehiclePhoto',
              onChanged: onVehiclePhoto,
            ),
            const SizedBox(height: 10),
            DocPickerField(
              label: 'Carte grise',
              fieldKey: 'carteGrise',
              onChanged: onCarteGrise,
            ),
            const SizedBox(height: 10),
            DocPickerField(
              label: "Attestation d'assurance",
              fieldKey: 'assurance',
              onChanged: onAssurance,
            ),
            const SizedBox(height: 10),

            // Date picker
            const _FieldLabel("Date d'expiration de l'assurance"),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: onPickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: insuranceExpiry != null
                        ? Colors.green.shade300
                        : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 18,
                      color: insuranceExpiry != null
                          ? Colors.green.shade600
                          : const Color(0xFF9CA3AF),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        insuranceExpiry != null
                            ? '${insuranceExpiry!.day.toString().padLeft(2, '0')}/${insuranceExpiry!.month.toString().padLeft(2, '0')}/${insuranceExpiry!.year}'
                            : 'Sélectionner une date',
                        style: TextStyle(
                          fontSize: 14,
                          color: insuranceExpiry != null
                              ? const Color(0xFF065F46)
                              : const Color(0xFF9CA3AF),
                          fontWeight: insuranceExpiry != null
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (insuranceExpiry != null)
                      Icon(
                        Icons.check_circle,
                        color: Colors.green.shade500,
                        size: 16,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Équipement
        _DocSection(
          icon: Icons.sports_motorsports_outlined,
          title: 'Équipement',
          color: const Color(0xFF6366F1),
          children: [
            DocPickerField(
              label: 'Photo casque',
              fieldKey: 'casquePhoto',
              onChanged: onCasquePhoto,
            ),
          ],
        ),
      ],
    ),
  );
}

// ── Étape 3 : Récap ───────────────────────────────────────────────────────────
class _Step3 extends StatelessWidget {
  final String name, phone;
  final int docsUploaded, docsTotal;
  final Map<String, String?> docs;
  final DateTime? insuranceExpiry;
  final String? error;
  const _Step3({
    required this.name,
    required this.phone,
    required this.docsUploaded,
    required this.docsTotal,
    required this.docs,
    required this.insuranceExpiry,
    required this.error,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepHeading(
          icon: Icons.checklist_rounded,
          title: 'Vérification',
          subtitle: 'Relisez avant de soumettre',
        ),
        const SizedBox(height: 20),

        // Infos livreur
        _RecapCard(
          children: [
            _RecapRow(
              icon: Icons.person_outline,
              label: 'Nom',
              value: name.isEmpty ? '—' : name,
            ),
            _RecapRow(
              icon: Icons.phone_outlined,
              label: 'Téléphone',
              value: phone,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Documents
        _RecapCard(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  const Text(
                    'Documents',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFF374151),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: docsUploaded == docsTotal
                          ? Colors.green.shade50
                          : AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$docsUploaded/$docsTotal ajoutés',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: docsUploaded == docsTotal
                            ? Colors.green.shade700
                            : AppColors.primaryMid,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ...docs.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      e.value != null
                          ? Icons.check_circle_outline
                          : Icons.radio_button_unchecked,
                      size: 16,
                      color: e.value != null
                          ? Colors.green.shade600
                          : Colors.grey.shade400,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      e.key,
                      style: TextStyle(
                        fontSize: 13,
                        color: e.value != null
                            ? const Color(0xFF1F2937)
                            : Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (insuranceExpiry != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 15,
                      color: Colors.green.shade600,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Assurance exp. : ${insuranceExpiry!.day.toString().padLeft(2, '0')}/${insuranceExpiry!.month.toString().padLeft(2, '0')}/${insuranceExpiry!.year}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),

        if (error != null) ...[
          const SizedBox(height: 16),
          Container(
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
                    error!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.20),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline,
                color: AppColors.primaryMid,
                size: 16,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Le livreur sera activé après validation admin. Vous serez notifié.',
                  style: TextStyle(fontSize: 12, color: AppColors.primaryMid),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ── Widgets utilitaires ───────────────────────────────────────────────────────

class _StepHeading extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  const _StepHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.15),
              AppColors.primaryMid.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.primaryMid, size: 22),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F2942),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    ],
  );
}

class _DocSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final List<Widget> children;
  const _DocSection({
    required this.icon,
    required this.title,
    required this.color,
    required this.children,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 15),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: color,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      ...children,
    ],
  );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Color(0xFF374151),
    ),
  );
}

class _RecapCard extends StatelessWidget {
  final List<Widget> children;
  const _RecapCard({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE5E7EB)),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

class _RecapRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _RecapRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primaryMid),
        const SizedBox(width: 8),
        Text(
          '$label : ',
          style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
        ),
      ],
    ),
  );
}

InputDecoration _inputDec(String hint, IconData icon, {String? error}) =>
    InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
      prefixIcon: Icon(icon, size: 18, color: const Color(0xFF9CA3AF)),
      filled: true,
      fillColor: const Color(0xFFF1F5F9),
      errorText: error,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    );
