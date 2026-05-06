import 'package:flutter/material.dart';

class AmbassadorPendingScreen extends StatelessWidget {
  const AmbassadorPendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.hourglass_top_rounded, color: Color(0xFF7C3AED), size: 40),
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
              const SizedBox(height: 32),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.18)),
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
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Ajouter des livreurs', style: TextStyle(fontWeight: FontWeight.w700)),
                  onPressed: () => Navigator.of(context).pushNamed('/ambassador/dashboard'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
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
      const Text('• ', style: TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.w700)),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF374151)))),
    ]),
  );
}
