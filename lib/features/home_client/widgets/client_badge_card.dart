import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';

// ── Config visuelle par tier — icônes Flutter au lieu d'emojis ───────────────
const _tiers = {
  'vip':     (name: 'DEM VIP',     icon: Icons.diamond_outlined,           color: Color(0xFF7C3AED), bg: Color(0xFFF5F0FF)),
  'buur':    (name: 'DEM Buur',    icon: Icons.workspace_premium_outlined, color: Color(0xFF7B1FA2), bg: Color(0xFFF3E5F5)),
  'djambar': (name: 'DEM Djambar', icon: Icons.emoji_events_outlined,      color: Color(0xFF1565C0), bg: Color(0xFFE3F2FD)),
  'mbokk':   (name: 'DEM Mbokk',  icon: Icons.star_outline_rounded,       color: Color(0xFF00695C), bg: Color(0xFFE0F2F1)),
  'xarit':   (name: 'DEM Xarit',  icon: Icons.handshake_outlined,         color: Color(0xFF0288D1), bg: Color(0xFFE1F5FE)),
  'classic': (name: 'DEM Classic', icon: Icons.verified_outlined,          color: Color(0xFF00838F), bg: Color(0xFFE0F7FA)),
};

class ClientBadgeCard extends StatelessWidget {
  final Map<String, dynamic> badgeData;
  const ClientBadgeCard({super.key, required this.badgeData});

  @override
  Widget build(BuildContext context) {
    final badge  = badgeData['badge']        as String?;
    final name   = badgeData['badgeName']    as String? ?? 'Nouveau';
    final next   = badgeData['nextProgress'] as Map<String, dynamic>?;

    final visual = badge != null ? _tiers[badge] : null;
    final color  = visual?.color ?? AppColors.primaryMid;
    final bg     = visual?.bg    ?? const Color(0xFFF0F9FF);
    final icon   = visual?.icon  ?? Icons.rocket_launch_outlined;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.20)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.10), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(children: [

        // ── Header horizontal : emblème + nom ────────────────────────────────
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          _BadgeEmblem(icon: icon, color: color),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color, letterSpacing: -0.3)),
            const SizedBox(height: 2),
            Text('Votre niveau fidélité',
              style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.60))),
          ]),
        ]),

        // ── Progression vers le prochain badge ───────────────────────────────
        if (next != null) ...[
          const SizedBox(height: 14),
          _Separator(color: color),
          const SizedBox(height: 12),
          _NextSection(next: next, color: color),
        ] else if (badge == 'vip') ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.auto_awesome_rounded, size: 15, color: color),
              const SizedBox(width: 6),
              Text('Niveau maximum atteint !',
                style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w700)),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ── Emblème du badge ──────────────────────────────────────────────────────────
class _BadgeEmblem extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _BadgeEmblem({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54, height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.30), width: 2),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 10, spreadRadius: 1)],
      ),
      child: Icon(icon, size: 26, color: color),
    );
  }
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
    final nextIcon    = nextVisual?.icon  ?? Icons.track_changes_rounded;
    final needsVal    = next['requiresValidation'] as bool? ?? false;

    final courses   = next['courses']   as Map<String, dynamic>?;
    final referrals = next['referrals'] as Map<String, dynamic>?;
    final rating    = next['rating']    as Map<String, dynamic>?;
    final profileC  = next['profileComplete'] as Map<String, dynamic>?;

    final cCur  = (courses?['current']   as num?)?.toInt() ?? 0;
    final cNeed = (courses?['needed']    as num?)?.toInt() ?? 1;
    final rCur  = (referrals?['current'] as num?)?.toInt() ?? 0;
    final rNeed = (referrals?['needed']  as num?)?.toInt() ?? 1;

    // Message motivant (sans emoji dans le texte)
    String? motivMsg;
    if (courses != null && cCur < cNeed) {
      final left = cNeed - cCur;
      motivMsg = 'Plus que $left course${left > 1 ? 's' : ''} pour débloquer $nextName !';
    } else if (referrals != null && rCur < rNeed) {
      final left = rNeed - rCur;
      motivMsg = 'Invite $left ami${left > 1 ? 's' : ''} pour débloquer $nextName !';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // En-tête "Prochain niveau"
      Row(children: [
        Text('Prochain niveau', style: ClientText.caption.copyWith(color: color.withValues(alpha: 0.65))),
        const Spacer(),
        Icon(nextIcon, size: 14, color: nextColor),
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
            Icon(Icons.track_changes_rounded, size: 16, color: nextColor),
            const SizedBox(width: 8),
            Expanded(child: Text(motivMsg,
              style: ClientText.labelStrong.copyWith(color: nextColor),
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
    final ratio = needed > 0 ? (current / needed).clamp(0.0, 1.0) : 1.0;
    final done  = current >= needed;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 13, color: done ? Colors.green.shade600 : color.withValues(alpha: 0.75)),
        const SizedBox(width: 5),
        Text(label, style: ClientText.label.copyWith(color: done ? Colors.green.shade600 : color.withValues(alpha: 0.80))),
        const Spacer(),
        if (done)
          Row(children: [
            Icon(Icons.check_circle, size: 14, color: Colors.green.shade600),
            const SizedBox(width: 4),
            Text('Complété !', style: ClientText.labelStrong.copyWith(color: Colors.green.shade600)),
          ])
        else
          Text('$current / $needed', style: ClientText.labelStrong.copyWith(color: color)),
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
      Icon(ok ? Icons.star_rounded : Icons.star_outline_rounded,
        size: 14, color: ok ? Colors.amber.shade600 : color.withValues(alpha: 0.70)),
      const SizedBox(width: 5),
      Text('Note moyenne', style: ClientText.label.copyWith(color: color.withValues(alpha: 0.80))),
      const Spacer(),
      Text('$current', style: ClientText.labelStrong.copyWith(color: ok ? Colors.amber.shade600 : color)),
      Text(' / $needed', style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.60))),
      const SizedBox(width: 3),
      Icon(Icons.star_rounded, size: 12, color: ok ? Colors.amber.shade600 : color.withValues(alpha: 0.60)),
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
    Text('Profil complet', style: ClientText.label.copyWith(color: color.withValues(alpha: 0.80))),
    const Spacer(),
    if (complete) ...[
      Icon(Icons.check_rounded, size: 13, color: Colors.green.shade600),
      const SizedBox(width: 3),
      Text('Oui', style: ClientText.labelStrong.copyWith(color: Colors.green.shade600)),
    ] else
      Text('Non (nom + email)', style: ClientText.labelStrong.copyWith(color: color)),
  ]);
}
