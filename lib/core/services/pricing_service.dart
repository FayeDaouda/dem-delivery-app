/// Calcule les frais DEM selon la grille tarifaire officielle (document stratégie S3).
///
/// Le livreur reçoit toujours `coursePrice` en totalité (0% commission).
/// DEM collecte `demFee` séparément auprès du client.
/// Le client paie : coursePrice + demFee.
class PricingService {
  static const _grid = [
    (900.0,   1250.0,  65.0),
    (1251.0,  1600.0,  90.0),
    (1601.0,  2000.0, 120.0),
    (2001.0,  2450.0, 155.0),
    (2451.0,  2750.0, 185.0),
    (2751.0,  3100.0, 215.0),
    (3101.0,  3490.0, 255.0),
    (3491.0,  3900.0, 295.0),
    (3901.0,  4450.0, 350.0),
    (4451.0,  5000.0, 425.0),
  ];

  /// Retourne les frais DEM pour un prix de course donné.
  /// Retourne 0 si le prix est inférieur à 900 FCFA (hors grille).
  /// Retourne 425 si le prix dépasse 5 000 FCFA.
  static double computeFee(double coursePrice) {
    for (final (min, max, fee) in _grid) {
      if (coursePrice >= min && coursePrice <= max) return fee;
    }
    if (coursePrice < 900) return 0;
    return 425;
  }

  /// Montant MLM redistribué au client (20% des frais).
  static double mlmCredit(double fee) => (fee * 0.20).roundToDouble();
}
