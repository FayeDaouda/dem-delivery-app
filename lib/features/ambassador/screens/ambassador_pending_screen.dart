import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../data/ambassador_repository.dart';

const _purple = Color(0xFF7C3AED);

class AmbassadorPendingScreen extends StatefulWidget {
  const AmbassadorPendingScreen({super.key});
  @override
  State<AmbassadorPendingScreen> createState() => _State();
}

class _State extends State<AmbassadorPendingScreen> {
  final _repo = AmbassadorRepository(ApiClient.dio);

  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final s = await _repo.getStats();
      if (mounted) setState(() => _stats = s);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final fleetSize = (_stats?['fleetSize'] as num?)?.toInt() ?? 0;
    final fleetMax  = (_stats?['fleetMax']  as num?)?.toInt() ?? 10;
    final atLimit   = fleetSize >= fleetMax;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),

              // ── Icône hourglass ──
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.hourglass_top_rounded, color: _purple, size: 40),
              ),
              const SizedBox(height: 28),

              const Text(
                'Dossier en cours de validation',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1E1B4B)),
              ),
              const SizedBox(height: 12),
              const Text(
                'Votre dossier a été soumis avec succès.\nL\'équipe DEM va le vérifier sous 24 à 48h.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.5),
              ),
              const SizedBox(height: 28),

              // ── Carte drivers ajoutés ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
                ),
                child: Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: _purple.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.group_outlined, color: _purple, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        '$fleetSize livreur${fleetSize != 1 ? 's' : ''} ajouté${fleetSize != 1 ? 's' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF1F2937)),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Ils seront activés après validation de votre compte.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ]),
                  ),
                ]),
              ),

              // ── Alerte limite flotte ──
              if (atLimit) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Limite atteinte : $fleetSize/$fleetMax livreurs. Vous pourrez demander une extension une fois votre compte validé.',
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                      ),
                    ),
                  ]),
                ),
              ],

              const SizedBox(height: 20),

              // ── Encart infos ──
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _purple.withValues(alpha: 0.18)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('En attendant, vous pouvez déjà :', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    SizedBox(height: 10),
                    _Bullet('Ajouter vos livreurs et leurs documents'),
                    _Bullet('Constituer votre flotte (jusqu\'à 10 motos)'),
                    _Bullet('Dès validation, ils seront activés automatiquement'),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Gérer mes livreurs', style: TextStyle(fontWeight: FontWeight.w700)),
                  onPressed: () => context.push('/ambassador/dashboard'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('• ', style: TextStyle(color: _purple, fontWeight: FontWeight.w700)),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF374151)))),
    ]),
  );
}
