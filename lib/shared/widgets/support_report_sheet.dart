import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/error/app_exception.dart';
import '../../features/deliveries/data/orders_repository.dart';
import 'support_contact_tile.dart';

// ── Types de problèmes ────────────────────────────────────────────────────────
class _Problem {
  final String id;
  final String emoji;
  final String label;
  final String severity; // critical | high | medium
  final List<String> roles;

  const _Problem(this.id, this.emoji, this.label, this.severity, this.roles);
}

// Le DEM Pro occupe exactement le rôle "clientId" d'une commande (comme
// CLIENT) — mêmes types de problèmes accessibles partout où CLIENT l'est.
const _kProblems = [
  _Problem('DRIVER_UNREACHABLE', '📵', 'Driver introuvable', 'critical', [
    'CLIENT',
    'DEM_PRO',
  ]),
  _Problem('PARCEL_LOST', '📦', 'Colis perdu', 'critical', [
    'CLIENT',
    'DEM_PRO',
    'DRIVER',
  ]),
  _Problem('ACCIDENT', '🚨', 'Accident / Urgence', 'critical', ['DRIVER']),
  _Problem('WRONG_DELIVERY', '❌', 'Mauvaise livraison', 'critical', [
    'CLIENT',
    'DEM_PRO',
  ]),
  _Problem('CLIENT_UNREACHABLE', '📞', 'Client injoignable', 'high', [
    'DRIVER',
  ]),
  _Problem('MAJOR_DELAY', '⏱', 'Retard important', 'high', [
    'CLIENT',
    'DEM_PRO',
    'DRIVER',
  ]),
  _Problem('WRONG_ADDRESS', '📍', 'Adresse incorrecte', 'high', [
    'CLIENT',
    'DEM_PRO',
    'DRIVER',
  ]),
  _Problem('CONTACT_IMPOSSIBLE', '🔕', 'Impossible de contacter', 'high', [
    'CLIENT',
    'DEM_PRO',
  ]),
  _Problem('INFO_REQUEST', '💬', "Demande d'information", 'medium', [
    'CLIENT',
    'DEM_PRO',
    'DRIVER',
  ]),
  _Problem('INSTRUCTION_CHANGE', '✏', 'Changement de consigne', 'medium', [
    'CLIENT',
    'DEM_PRO',
    'DRIVER',
  ]),
  _Problem('OTHER', '🔸', 'Autre problème', 'medium', [
    'CLIENT',
    'DEM_PRO',
    'DRIVER',
  ]),
];

Color _sevColor(String sev) => switch (sev) {
  'critical' => const Color(0xFFEF4444),
  'high' => const Color(0xFFF97316),
  _ => const Color(0xFFF59E0B),
};

// ── Widget principal ──────────────────────────────────────────────────────────
class SupportReportSheet extends StatefulWidget {
  final String orderId;
  final String role;
  final OrdersRepository repo;

  const SupportReportSheet({
    super.key,
    required this.orderId,
    required this.role,
    required this.repo,
  });

  static Future<void> show(
    BuildContext context, {
    required String orderId,
    required String role,
    required OrdersRepository repo,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          SupportReportSheet(orderId: orderId, role: role, repo: repo),
    );
  }

  @override
  State<SupportReportSheet> createState() => _SupportReportSheetState();
}

class _SupportReportSheetState extends State<SupportReportSheet> {
  _Problem? _selected;
  final _msgCtrl = TextEditingController();
  bool _sending = false;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  List<_Problem> get _visible =>
      _kProblems.where((p) => p.roles.contains(widget.role)).toList();

  Future<void> _submit() async {
    if (_selected == null || _sending) return;
    setState(() => _sending = true);
    try {
      final result = await widget.repo.reportIssue(
        widget.orderId,
        type: _selected!.id,
        message: _msgCtrl.text.trim().isEmpty ? null : _msgCtrl.text.trim(),
      );
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openWhatsApp(String wa) async {
    final msg = Uri.encodeComponent(
      'Bonjour, je signale un problème avec ma course #${widget.orderId}. '
      'Type : ${_selected?.label ?? "—"}.',
    );
    final uri = Uri.parse('https://wa.me/$wa?text=$msg');
    if (await canLaunchUrl(uri))
      await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ── Sections de types groupées par sévérité ───────────────────────────────
  List<Widget> _buildSections() {
    final sections = <Widget>[];
    for (final (sev, label) in [
      ('critical', '🔴 Critique'),
      ('high', '🟠 Logistique'),
      ('medium', '🟡 Information'),
    ]) {
      final filtered = _visible.where((p) => p.severity == sev).toList();
      if (filtered.isEmpty) continue;

      sections.add(
        Text(
          label,
          style: TextStyle(
            color: _sevColor(sev).withValues(alpha: 0.90),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      );
      sections.add(const SizedBox(height: 8));
      sections.add(
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: filtered.map((p) {
            final isSelected = _selected?.id == p.id;
            final col = _sevColor(p.severity);
            return GestureDetector(
              onTap: () => setState(() => _selected = p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? col.withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? col
                        : Colors.white.withValues(alpha: 0.25),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p.emoji, style: const TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(
                      p.label,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.80),
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      );
      sections.add(const SizedBox(height: 16));
    }
    return sections;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0CB8DE), Color(0xFF0671BA), Color(0xFF04317C)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 28),
      child: SingleChildScrollView(
        child: _result != null ? _buildSuccess() : _buildForm(),
      ),
    );
  }

  // ── Écran succès ──────────────────────────────────────────────────────────
  Widget _buildSuccess() {
    final support = _result!['support'] as Map?;
    final phone = support?['phone'] as String? ?? AppConfig.supportPhone;
    final wa = support?['whatsapp'] as String? ?? AppConfig.supportWhatsapp;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Handle(),
        const SizedBox(height: 20),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E).withValues(alpha: 0.20),
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF22C55E).withValues(alpha: 0.50),
            ),
          ),
          child: const Icon(
            Icons.check_circle_outline,
            color: Color(0xFF22C55E),
            size: 34,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Signalement reçu',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _result!['message'] as String? ?? 'Notre équipe a été informée.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 13,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Contacter le support directement',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SupportContactTile(
          icon: Icons.phone_rounded,
          color: const Color(0xFF22C55E),
          label: 'Appeler le support',
          subtitle: phone,
          onTap: () => _openPhone(phone),
        ),
        const SizedBox(height: 10),
        SupportContactTile(
          icon: Icons.chat_rounded,
          color: const Color(0xFF25D366),
          label: 'WhatsApp support',
          subtitle: 'Message pré-rempli',
          onTap: () => _openWhatsApp(wa),
        ),
        const SizedBox(height: 20),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Fermer',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.50),
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  // ── Formulaire ────────────────────────────────────────────────────────────
  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Handle(),
        const SizedBox(height: 16),
        const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'Signaler un problème',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Sélectionnez le type de problème. Notre équipe sera immédiatement informée.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),

        // Sections par sévérité
        ..._buildSections(),

        // Message optionnel
        if (_selected != null) ...[
          Text(
            'Détails (optionnel)',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.70),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _msgCtrl,
            maxLines: 3,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Décrivez le problème brièvement…',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.40),
                fontSize: 13,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.25),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.25),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Bouton envoyer
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _selected == null || _sending ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.20),
              foregroundColor: const Color(0xFF0671BA),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: _sending
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF0671BA),
                    ),
                  )
                : Text(
                    _selected == null
                        ? 'Choisissez un type de problème'
                        : 'Envoyer le signalement',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Annuler',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Widgets internes ──────────────────────────────────────────────────────────
class _Handle extends StatelessWidget {
  const _Handle();
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: 3,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}
