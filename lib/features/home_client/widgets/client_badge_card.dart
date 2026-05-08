import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

// ── Config visuelle par tier ──────────────────────────────────────────────────
const _tiers = {
  'vip':     (name: 'DEM VIP',     emoji: '💎', color: Color(0xFF7C3AED), bg: Color(0xFFF5F0FF)),
  'buur':    (name: 'DEM Buur',    emoji: '👑', color: Color(0xFF7B1FA2), bg: Color(0xFFF3E5F5)),
  'djambar': (name: 'DEM Djambar', emoji: '🏆', color: Color(0xFF1565C0), bg: Color(0xFFE3F2FD)),
  'mbokk':   (name: 'DEM Mbokk',  emoji: '⭐', color: Color(0xFF00695C), bg: Color(0xFFE0F2F1)),
  'xarit':   (name: 'DEM Xarit',  emoji: '🤝', color: Color(0xFF0288D1), bg: Color(0xFFE1F5FE)),
  'classic': (name: 'DEM Classic', emoji: '✅', color: Color(0xFF00838F), bg: Color(0xFFE0F7FA)),
};

class ClientBadgeCard extends StatelessWidget {
  final Map<String, dynamic> badgeData;
  const ClientBadgeCard({super.key, required this.badgeData});

  @override
  Widget build(BuildContext context) {
    final badge    = badgeData['badge']    as String?;
    final name     = badgeData['badgeName'] as String? ?? 'Nouveau';
    final next     = badgeData['nextProgress'] as Map<String, dynamic>?;
    final stats    = badgeData['stats']    as Map<String, dynamic>? ?? {};

    final visual  = badge != null ? _tiers[badge] : null;
    final color   = visual?.color ?? AppColors.primaryMid;
    final bg      = visual?.bg    ?? const Color(0xFFF0F9FF);
    final emoji   = visual?.emoji ?? '🚀';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Mon badge', style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.70), fontWeight: FontWeight.w600)),
              Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
            ]),
            const Spacer(),
            // Stats rapides
            _StatChip(icon: Icons.motorcycle, value: '${stats['courses'] ?? 0}', label: 'courses', color: color),
            const SizedBox(width: 8),
            _StatChip(icon: Icons.people_outline, value: '${stats['referrals'] ?? 0}', label: 'filleuls', color: color),
          ]),

          // Progression vers le prochain badge
          if (next != null) ...[
            const SizedBox(height: 14),
            _Divider(color: color),
            const SizedBox(height: 12),
            _NextBadgeProgress(next: next, color: color),
          ] else if (badge == 'vip') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
              child: Text('✨ Niveau maximum atteint !', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }
}

class _NextBadgeProgress extends StatelessWidget {
  final Map<String, dynamic> next;
  final Color color;
  const _NextBadgeProgress({required this.next, required this.color});

  @override
  Widget build(BuildContext context) {
    final nextName  = next['tierName']  as String? ?? '';
    final courses   = next['courses']   as Map<String, dynamic>?;
    final referrals = next['referrals'] as Map<String, dynamic>?;
    final rating    = next['rating']    as Map<String, dynamic>?;
    final profileC  = next['profileComplete'] as Map<String, dynamic>?;
    final needsVal  = next['requiresValidation'] as bool? ?? false;

    final cCur = (courses?['current']   as num?)?.toInt() ?? 0;
    final cNeed = (courses?['needed']   as num?)?.toInt() ?? 1;
    final rCur = (referrals?['current'] as num?)?.toInt() ?? 0;
    final rNeed = (referrals?['needed'] as num?)?.toInt() ?? 1;

    final nextVisual = _tiers[next['tierId'] as String? ?? ''];
    final nextColor  = nextVisual?.color ?? color;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Vers ', style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.70))),
        Text(nextVisual?.emoji ?? '🎯', style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
        Text(nextName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: nextColor)),
        if (needsVal) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
            child: const Text('validation requise', style: TextStyle(fontSize: 9, color: Colors.orange, fontWeight: FontWeight.w700)),
          ),
        ],
      ]),
      const SizedBox(height: 10),

      if (courses != null)
        _ProgressRow(
          icon: Icons.motorcycle, label: 'Courses',
          current: cCur, needed: cNeed, color: color,
        ),
      if (referrals != null) ...[
        const SizedBox(height: 6),
        _ProgressRow(
          icon: Icons.people_outline, label: 'Filleuls',
          current: rCur, needed: rNeed, color: color,
        ),
      ],
      if (rating != null) ...[
        const SizedBox(height: 6),
        _RatingRow(current: (rating['current'] as num?)?.toDouble() ?? 0, needed: (rating['needed'] as num?)?.toDouble() ?? 0, color: color),
      ],
      if (profileC != null) ...[
        const SizedBox(height: 6),
        _ProfileRow(complete: profileC['current'] as bool? ?? false, color: color),
      ],
    ]);
  }
}

class _ProgressRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int current, needed;
  final Color color;
  const _ProgressRow({required this.icon, required this.label, required this.current, required this.needed, required this.color});

  @override
  Widget build(BuildContext context) {
    final ratio = needed > 0 ? (current / needed).clamp(0.0, 1.0) : 1.0;
    final remaining = (needed - current).clamp(0, needed);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 12, color: color.withValues(alpha: 0.70)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.70))),
        const Spacer(),
        Text('$current / $needed', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: ratio,
          minHeight: 5,
          backgroundColor: color.withValues(alpha: 0.12),
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
      if (remaining > 0)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('encore $remaining', style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.60))),
        ),
    ]);
  }
}

class _RatingRow extends StatelessWidget {
  final double current, needed;
  final Color color;
  const _RatingRow({required this.current, required this.needed, required this.color});

  @override
  Widget build(BuildContext context) {
    final ok = current >= needed;
    return Row(children: [
      Icon(Icons.star_outline, size: 12, color: ok ? Colors.amber : color.withValues(alpha: 0.70)),
      const SizedBox(width: 4),
      Text('Note', style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.70))),
      const Spacer(),
      Text('$current / $needed ★', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ok ? Colors.amber : color)),
    ]);
  }
}

class _ProfileRow extends StatelessWidget {
  final bool complete;
  final Color color;
  const _ProfileRow({required this.complete, required this.color});

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(complete ? Icons.check_circle_outline : Icons.person_outline, size: 12, color: complete ? Colors.green : color.withValues(alpha: 0.70)),
    const SizedBox(width: 4),
    Text('Profil complet', style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.70))),
    const Spacer(),
    Text(complete ? '✓ Oui' : 'Non (nom + email requis)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: complete ? Colors.green : color)),
  ]);
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value, label;
  final Color color;
  const _StatChip({required this.icon, required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
    Text(label, style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.60))),
  ]);
}

class _Divider extends StatelessWidget {
  final Color color;
  const _Divider({required this.color});

  @override
  Widget build(BuildContext context) => Divider(color: color.withValues(alpha: 0.15), height: 1);
}
