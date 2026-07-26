import 'package:flutter/material.dart';

enum DriverBadge { none, xarit, mbokk, doorWarr, domouNdey, buur, gainde }

/// Une ligne de critères (AND entre courses/parrainages/note).
/// Un badge peut avoir plusieurs lignes alternatives (OR entre les lignes).
class BadgeCriteria {
  final int coursesRequired;
  final int referralsRequired;
  final double ratingRequired;

  const BadgeCriteria({
    required this.coursesRequired,
    required this.referralsRequired,
    required this.ratingRequired,
  });

  bool isMetBy({required int courses, required int referrals, required double rating}) {
    final meetsRating    = ratingRequired == 0 || rating >= ratingRequired;
    final meetsCourses   = courses >= coursesRequired;
    final meetsReferrals = referrals >= referralsRequired;
    return meetsCourses && meetsReferrals && meetsRating;
  }
}

class BadgeInfo {
  final DriverBadge tier;
  final String name;
  final String subtitle;
  final Color color;
  final Color bgColor;
  final IconData icon;
  final List<BadgeCriteria> criteria;

  const BadgeInfo({
    required this.tier,
    required this.name,
    required this.subtitle,
    required this.color,
    required this.bgColor,
    required this.icon,
    required this.criteria,
  });

  bool isMetBy({required int courses, required int referrals, required double rating}) {
    return criteria.any((c) => c.isMetBy(courses: courses, referrals: referrals, rating: rating));
  }
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
      criteria: [BadgeCriteria(coursesRequired: 500, referralsRequired: 0, ratingRequired: 4.2)],
    ),
    BadgeInfo(
      tier: DriverBadge.buur,
      name: 'DEM Buur',
      subtitle: '10 courses garanties/sem + casque DEM',
      color: Color(0xFF9C27B0),
      bgColor: Color(0xFFF3E5F5),
      icon: Icons.workspace_premium,
      criteria: [BadgeCriteria(coursesRequired: 300, referralsRequired: 0, ratingRequired: 4.0)],
    ),
    BadgeInfo(
      tier: DriverBadge.domouNdey,
      name: 'DEM Domou Ndey',
      subtitle: '8 courses garanties/sem',
      color: Color(0xFF1565C0),
      bgColor: Color(0xFFE3F2FD),
      icon: Icons.star,
      criteria: [BadgeCriteria(coursesRequired: 135, referralsRequired: 0, ratingRequired: 4.0)],
    ),
    BadgeInfo(
      tier: DriverBadge.doorWarr,
      name: 'DEM Door Warr',
      subtitle: '6 courses garanties/sem',
      color: Color(0xFF0097A7),
      bgColor: Color(0xFFE0F7FA),
      icon: Icons.verified,
      criteria: [BadgeCriteria(coursesRequired: 70, referralsRequired: 0, ratingRequired: 3.5)],
    ),
    BadgeInfo(
      tier: DriverBadge.mbokk,
      name: 'DEM Mbokk',
      subtitle: 'Tenue DEM offerte + badge vérifié',
      color: Color(0xFF00897B),
      bgColor: Color(0xFFE0F2F1),
      icon: Icons.groups,
      criteria: [BadgeCriteria(coursesRequired: 30, referralsRequired: 12, ratingRequired: 3.5)],
    ),
    BadgeInfo(
      tier: DriverBadge.xarit,
      name: 'DEM Xarit',
      subtitle: 'Priorité sur les courses',
      color: Color(0xFF0CB8DE),
      bgColor: Color(0xFFE1F5FE),
      icon: Icons.handshake_outlined,
      criteria: [
        BadgeCriteria(coursesRequired: 3, referralsRequired: 0, ratingRequired: 0),
        BadgeCriteria(coursesRequired: 0, referralsRequired: 3, ratingRequired: 0),
      ],
    ),
    BadgeInfo(
      tier: DriverBadge.none,
      name: 'Nouveau livreur',
      subtitle: 'Faites votre première course pour obtenir votre badge',
      color: Color(0xFF90A4AE),
      bgColor: Color(0xFFECEFF1),
      icon: Icons.directions_bike,
      criteria: [BadgeCriteria(coursesRequired: 0, referralsRequired: 0, ratingRequired: 0)],
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
      if (badge.isMetBy(courses: courses, referrals: referrals, rating: rating)) return badge;
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
      final rawCriteria = j['criteria'] as List<dynamic>?;
      final criteria = (rawCriteria != null && rawCriteria.isNotEmpty)
          ? rawCriteria.map((c) {
              final m = c as Map<String, dynamic>;
              return BadgeCriteria(
                coursesRequired:   (m['courses']   as num?)?.toInt()    ?? 0,
                referralsRequired: (m['referrals'] as num?)?.toInt()    ?? 0,
                ratingRequired:    (m['rating']    as num?)?.toDouble() ?? 0,
              );
            }).toList()
          : fallback.criteria;
      return BadgeInfo(
        tier:     tier,
        name:     j['name']      as String? ?? fallback.name,
        subtitle: j['advantage'] as String? ?? fallback.subtitle,
        color:    fallback.color,
        bgColor:  fallback.bgColor,
        icon:     fallback.icon,
        criteria: criteria,
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

  /// Score de "distance restante" d'une ligne de critères par rapport aux stats actuelles
  /// (0 = déjà rempli, plus c'est haut plus il reste de chemin).
  static double _gap(BadgeCriteria c, {required int courses, required int referrals, required double rating}) {
    double gap = 0;
    if (c.coursesRequired > 0)   gap += 1 - (courses / c.coursesRequired).clamp(0.0, 1.0);
    if (c.referralsRequired > 0) gap += 1 - (referrals / c.referralsRequired).clamp(0.0, 1.0);
    if (c.ratingRequired > 0)    gap += 1 - (rating / c.ratingRequired).clamp(0.0, 1.0);
    return gap;
  }

  /// Parmi les lignes alternatives d'un badge, retourne celle la plus proche d'être validée
  /// vu les stats actuelles du driver — sert à afficher un objectif unique dans l'UI.
  static BadgeCriteria closestCriteria(
    BadgeInfo badge, {
    required int courses,
    required int referrals,
    required double rating,
  }) {
    return badge.criteria.reduce((a, b) =>
        _gap(a, courses: courses, referrals: referrals, rating: rating) <=
                _gap(b, courses: courses, referrals: referrals, rating: rating)
            ? a
            : b);
  }

  /// Libellé de l'objectif le plus proche (le critère le moins avancé de la ligne choisie),
  /// ex: "3 courses" ou "3 parrainages".
  static String objectiveLabel(
    BadgeCriteria row, {
    required int courses,
    required int referrals,
    required double rating,
  }) {
    final entries = <MapEntry<String, double>>[];
    if (row.coursesRequired > 0) {
      entries.add(MapEntry('${row.coursesRequired} courses', (courses / row.coursesRequired).clamp(0.0, 1.0)));
    }
    if (row.referralsRequired > 0) {
      entries.add(MapEntry('${row.referralsRequired} parrainages', (referrals / row.referralsRequired).clamp(0.0, 1.0)));
    }
    if (row.ratingRequired > 0) {
      entries.add(MapEntry('note ${row.ratingRequired}', (rating / row.ratingRequired).clamp(0.0, 1.0)));
    }
    if (entries.isEmpty) return '';
    entries.sort((a, b) => a.value.compareTo(b.value));
    return entries.first.key;
  }

  /// Progression (0.0 → 1.0) vers le badge suivant, basée sur la ligne de critères
  /// la plus proche d'être atteinte.
  static double progressToNext({
    required int courses,
    required int referrals,
    required double rating,
    required DriverBadge current,
  }) {
    final nextBadge = next(current);
    if (nextBadge == null) return 1.0;
    final row = closestCriteria(nextBadge, courses: courses, referrals: referrals, rating: rating);
    final parts = <double>[];
    if (row.coursesRequired > 0)   parts.add((courses / row.coursesRequired).clamp(0.0, 1.0));
    if (row.referralsRequired > 0) parts.add((referrals / row.referralsRequired).clamp(0.0, 1.0));
    if (row.ratingRequired > 0)    parts.add((rating / row.ratingRequired).clamp(0.0, 1.0));
    if (parts.isEmpty) return 1.0;
    return parts.reduce((a, b) => a < b ? a : b);
  }
}
