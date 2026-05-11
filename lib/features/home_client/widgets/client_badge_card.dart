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
    final badge  = badgeData['badge']     as String?;
    final name   = badgeData['badgeName'] as String? ?? 'Nouveau';
    final next   = badgeData['nextProgress'] as Map<String, dynamic>?;
    final stats  = badgeData['stats']     as Map<String, dynamic>? ?? {};

    final visual = badge != null ? _tiers[badge] : null;
    final color  = visual?.color ?? AppColors.primaryMid;
    final bg     = visual?.bg    ?? const Color(0xFFF0F9FF);
    final emoji  = visual?.emoji ?? '🚀';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.20)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.10), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(children: [

        // ── Emblème centré ───────────────────────────────────────────────────
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _BadgeEmblem(emoji: emoji, color: color),
        ]),
        const SizedBox(height: 12),

        // ── Nom du badge ─────────────────────────────────────────────────────
        Text(name,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color, letterSpacing: -0.3),
          textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text('Votre niveau fidélité',
          style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.60)),
          textAlign: TextAlign.center),
        const SizedBox(height: 16),

        // ── Stats rapides ────────────────────────────────────────────────────
        Row(children: [
          Expanded(child: _StatPill(icon: Icons.motorcycle_outlined, value: '${stats['courses'] ?? 0}', label: 'courses', color: color)),
          const SizedBox(width: 10),
          Expanded(child: _StatPill(icon: Icons.people_outline,      value: '${stats['referrals'] ?? 0}', label: 'filleuls', color: color)),
        ]),

        // ── Progression vers le prochain badge ───────────────────────────────
        if (next != null) ...[
          const SizedBox(height: 18),
          _Separator(color: color),
          const SizedBox(height: 16),
          _NextSection(next: next, color: color),
        ] else if (badge == 'vip') ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
            child: Text('✨ Niveau maximum atteint !',
              style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          ),
        ],
      ]),
    );
  }
}

// ── Emblème du badge ──────────────────────────────────────────────────────────
class _BadgeEmblem extends StatelessWidget {
  final String emoji;
  final Color color;
  const _BadgeEmblem({required this.emoji, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72, height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.30), width: 2),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 12, spreadRadius: 2)],
      ),
      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 34))),
    );
  }
}

// ── Pill de stat ──────────────────────────────────────────────────────────────
class _StatPill extends StatelessWidget {
  final IconData icon;
  final String value, label;
  final Color color;
  const _StatPill({required this.icon, required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.15)),
    ),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 16, color: color.withValues(alpha: 0.75)),
      const SizedBox(width: 6),
      Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.65))),
    ]),
  );
}

// ── Séparateur ────────────────────────────────────────────────────────────────
class _Separator extends StatelessWidget {
  final Color color;
  const _Separator({required this.color});
  @override
  Widget build(BuildContext context) => Divider(color: color.withValues(alpha: 0.15), height: 1);
}

// ── Section progression vers le prochain niveau ───────────────────────────────
class _NextSection extends StatelessWidget {
  final Map<String, dynamic> next;
  final Color color;
  const _NextSection({required this.next, required this.color});

  @override
  Widget build(BuildContext context) {
    final nextVisual  = _tiers[next['tierId'] as String? ?? ''];
    final nextName    = next['tierName'] as String? ?? '';
    final nextColor   = nextVisual?.color ?? color;
    final nextEmoji   = nextVisual?.emoji ?? '🎯';
    final needsVal    = next['requiresValidation'] as bool? ?? false;

    final courses   = next['courses']   as Map<String, dynamic>?;
    final referrals = next['referrals'] as Map<String, dynamic>?;
    final rating    = next['rating']    as Map<String, dynamic>?;
    final profileC  = next['profileComplete'] as Map<String, dynamic>?;

    final cCur  = (courses?['current']   as num?)?.toInt() ?? 0;
    final cNeed = (courses?['needed']    as num?)?.toInt() ?? 1;
    final rCur  = (referrals?['current'] as num?)?.toInt() ?? 0;
    final rNeed = (referrals?['needed']  as num?)?.toInt() ?? 1;

    // Message motivant pour le critère le plus proche
    String? motivMsg;
    if (courses != null && cCur < cNeed) {
      final left = cNeed - cCur;
      motivMsg = 'Plus que $left course${left > 1 ? 's' : ''} pour débloquer $nextEmoji $nextName !';
    } else if (referrals != null && rCur < rNeed) {
      final left = rNeed - rCur;
      motivMsg = 'Invite $left ami${left > 1 ? 's' : ''} pour débloquer $nextEmoji $nextName !';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // En-tête "Vers …"
      Row(children: [
        Text('Prochain niveau', style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.65), fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(nextEmoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 5),
        Text(nextName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: nextColor)),
        if (needsVal) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
            child: const Text('validation', style: TextStyle(fontSize: 9, color: Colors.orange, fontWeight: FontWeight.w700)),
          ),
        ],
      ]),
      const SizedBox(height: 14),

      // Barres de progression indépendantes
      if (courses != null)
        _ProgressBar(icon: Icons.motorcycle_outlined, label: 'Courses', current: cCur, needed: cNeed, color: color),
      if (referrals != null) ...[
        const SizedBox(height: 10),
        _ProgressBar(icon: Icons.people_outline, label: 'Filleuls', current: rCur, needed: rNeed, color: color),
      ],
      if (rating != null) ...[
        const SizedBox(height: 8),
        _RatingLine(current: (rating['current'] as num?)?.toDouble() ?? 0, needed: (rating['needed'] as num?)?.toDouble() ?? 0, color: color),
      ],
      if (profileC != null) ...[
        const SizedBox(height: 8),
        _ProfileLine(complete: profileC['current'] as bool? ?? false, color: color),
      ],

      // CTA motivant
      if (motivMsg != null) ...[
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: nextColor.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: nextColor.withValues(alpha: 0.20)),
          ),
          child: Row(children: [
            Text('🎯', style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(child: Text(motivMsg,
              style: TextStyle(fontSize: 12, color: nextColor, fontWeight: FontWeight.w700),
            )),
          ]),
        ),
      ],
    ]);
  }
}

// ── Barre de progression individuelle ─────────────────────────────────────────
class _ProgressBar extends StatelessWidget {
  final IconData icon;
  final String label;
  final int current, needed;
  final Color color;
  const _ProgressBar({required this.icon, required this.label, required this.current, required this.needed, required this.color});

  @override
  Widget build(BuildContext context) {
    final ratio     = needed > 0 ? (current / needed).clamp(0.0, 1.0) : 1.0;
    final done      = current >= needed;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 13, color: done ? Colors.green.shade600 : color.withValues(alpha: 0.75)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: done ? Colors.green.shade600 : color.withValues(alpha: 0.80))),
        const Spacer(),
        if (done)
          Row(children: [
            Icon(Icons.check_circle, size: 14, color: Colors.green.shade600),
            const SizedBox(width: 4),
            Text('Complété !', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.green.shade600)),
          ])
        else
          Text('$current / $needed', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: ratio,
          minHeight: 7,
          backgroundColor: color.withValues(alpha: 0.10),
          valueColor: AlwaysStoppedAnimation<Color>(done ? Colors.green.shade500 : color),
        ),
      ),
    ]);
  }
}

// ── Ligne note ────────────────────────────────────────────────────────────────
class _RatingLine extends StatelessWidget {
  final double current, needed;
  final Color color;
  const _RatingLine({required this.current, required this.needed, required this.color});

  @override
  Widget build(BuildContext context) {
    final ok = current >= needed;
    return Row(children: [
      Icon(ok ? Icons.star : Icons.star_outline, size: 14, color: ok ? Colors.amber.shade600 : color.withValues(alpha: 0.70)),
      const SizedBox(width: 5),
      Text('Note moyenne', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.80))),
      const Spacer(),
      Text('$current / $needed ★', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ok ? Colors.amber.shade600 : color)),
    ]);
  }
}

// ── Ligne profil complet ──────────────────────────────────────────────────────
class _ProfileLine extends StatelessWidget {
  final bool complete;
  final Color color;
  const _ProfileLine({required this.complete, required this.color});

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(complete ? Icons.check_circle_outline : Icons.person_outline,
      size: 14, color: complete ? Colors.green.shade600 : color.withValues(alpha: 0.70)),
    const SizedBox(width: 5),
    Text('Profil complet', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.80))),
    const Spacer(),
    Text(complete ? '✓ Oui' : 'Non (nom + email)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: complete ? Colors.green.shade600 : color)),
  ]);
}
