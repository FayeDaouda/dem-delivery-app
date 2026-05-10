import 'package:flutter/material.dart';

enum DriverBadge { none, xarit, mbokk, doorWarr, domouNdey, buur, gainde }

class BadgeInfo {
  final DriverBadge tier;
  final String name;
  final String subtitle;
  final Color color;
  final Color bgColor;
  final IconData icon;
  final int coursesRequired;
  final int referralsRequired;
  final double ratingRequired;

  const BadgeInfo({
    required this.tier,
    required this.name,
    required this.subtitle,
    required this.color,
    required this.bgColor,
    required this.icon,
    required this.coursesRequired,
    required this.referralsRequired,
    required this.ratingRequired,
  });
}

class BadgeService {
  static const List<BadgeInfo> badges = [
    BadgeInfo(
      tier: DriverBadge.gainde,
      name: 'DEM Gainde',
      subtitle: '12 courses garanties/sem + chef de flotte',
      color: Color(0xFFFFD700),
      bgColor: Color(0xFFFFF8E1),
      icon: Icons.military_tech,
      coursesRequired: 500,
      referralsRequired: 0,
      ratingRequired: 4.2,
    ),
    BadgeInfo(
      tier: DriverBadge.buur,
      name: 'DEM Buur',
      subtitle: '10 courses garanties/sem + casque DEM',
      color: Color(0xFF9C27B0),
      bgColor: Color(0xFFF3E5F5),
      icon: Icons.workspace_premium,
      coursesRequired: 300,
      referralsRequired: 0,
      ratingRequired: 4.0,
    ),
    BadgeInfo(
      tier: DriverBadge.domouNdey,
      name: 'DEM Domou Ndey',
      subtitle: '8 courses garanties/sem',
      color: Color(0xFF1565C0),
      bgColor: Color(0xFFE3F2FD),
      icon: Icons.star,
      coursesRequired: 135,
      referralsRequired: 0,
      ratingRequired: 4.0,
    ),
    BadgeInfo(
      tier: DriverBadge.doorWarr,
      name: 'DEM Door Warr',
      subtitle: '6 courses garanties/sem',
      color: Color(0xFF0097A7),
      bgColor: Color(0xFFE0F7FA),
      icon: Icons.verified,
      coursesRequired: 70,
      referralsRequired: 0,
      ratingRequired: 3.5,
    ),
    BadgeInfo(
      tier: DriverBadge.mbokk,
      name: 'DEM Mbokk',
      subtitle: 'Tenue DEM offerte + badge vérifié',
      color: Color(0xFF00897B),
      bgColor: Color(0xFFE0F2F1),
      icon: Icons.groups,
      coursesRequired: 30,
      referralsRequired: 12,
      ratingRequired: 3.5,
    ),
    BadgeInfo(
      tier: DriverBadge.xarit,
      name: 'DEM Xarit',
      subtitle: 'Priorité sur les courses',
      color: Color(0xFF0CB8DE),
      bgColor: Color(0xFFE1F5FE),
      icon: Icons.handshake_outlined,
      coursesRequired: 3,
      referralsRequired: 3,
      ratingRequired: 0,
    ),
    BadgeInfo(
      tier: DriverBadge.none,
      name: 'Nouveau driver',
      subtitle: 'Effectuez vos premières courses',
      color: Color(0xFF90A4AE),
      bgColor: Color(0xFFECEFF1),
      icon: Icons.directions_bike,
      coursesRequired: 0,
      referralsRequired: 0,
      ratingRequired: 0,
    ),
  ];

  /// Retourne le badge actuel selon les stats du driver.
  /// [remoteConfig] : liste JSON depuis l'API (optionnel) — override les seuils hardcodés.
  static BadgeInfo compute({
    required int courses,
    required int referrals,
    required double rating,
    List<Map<String, dynamic>>? remoteConfig,
  }) {
    final tiers = remoteConfig != null ? _fromRemote(remoteConfig) : badges;
    for (final badge in tiers) {
      if (badge.tier == DriverBadge.none) break;
      final meetsRating    = badge.ratingRequired == 0 || rating >= badge.ratingRequired;
      final meetsCourses   = courses >= badge.coursesRequired;
      final meetsReferrals = referrals >= badge.referralsRequired;
      if (meetsCourses && meetsReferrals && meetsRating) return badge;
    }
    return tiers.last;
  }

  /// Convertit la config JSON de l'API en liste de BadgeInfo.
  static List<BadgeInfo> _fromRemote(List<Map<String, dynamic>> config) {
    const tierMap = {
      'gainde':    DriverBadge.gainde,
      'buur':      DriverBadge.buur,
      'domouNdey': DriverBadge.domouNdey,
      'doorWarr':  DriverBadge.doorWarr,
      'mbokk':     DriverBadge.mbokk,
      'xarit':     DriverBadge.xarit,
    };
    final result = config.map((j) {
      final tier    = tierMap[j['tier']] ?? DriverBadge.none;
      final fallback = badges.firstWhere((b) => b.tier == tier, orElse: () => badges.last);
      return BadgeInfo(
        tier:              tier,
        name:              j['name']     as String? ?? fallback.name,
        subtitle:          fallback.subtitle,
        color:             fallback.color,
        bgColor:           fallback.bgColor,
        icon:              fallback.icon,
        coursesRequired:   (j['courses']   as num?)?.toInt() ?? fallback.coursesRequired,
        referralsRequired: (j['referrals'] as num?)?.toInt() ?? fallback.referralsRequired,
        ratingRequired:    (j['rating']    as num?)?.toDouble() ?? fallback.ratingRequired,
      );
    }).toList();
    // Toujours terminer par 'none'
    if (result.isEmpty || result.last.tier != DriverBadge.none) {
      result.add(badges.last);
    }
    return result;
  }

  /// Retourne le badge suivant (null si déjà au maximum).
  static BadgeInfo? next(DriverBadge current) {
    final idx = badges.indexWhere((b) => b.tier == current);
    if (idx <= 0) return null;
    return badges[idx - 1];
  }

  /// Progression (0.0 → 1.0) vers le badge suivant, basée sur les courses.
  static double progressToCourses({
    required int courses,
    required DriverBadge current,
  }) {
    final nextBadge = next(current);
    if (nextBadge == null) return 1.0;
    final currentInfo = badges.firstWhere((b) => b.tier == current);
    final from = currentInfo.coursesRequired;
    final to   = nextBadge.coursesRequired;
    if (to <= from) return 1.0;
    return ((courses - from) / (to - from)).clamp(0.0, 1.0);
  }
}
