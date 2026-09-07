/// Formate un montant en FCFA avec séparateur de milliers (espace, convention
/// française) — "12500" → "12 500 FCFA". Utilisé partout où un prix est
/// affiché côté client (pas de dépendance `intl` pour un besoin aussi simple).
String formatFcfa(num amount, {bool withSuffix = true}) {
  final rounded = amount.round();
  final digits = rounded.abs().toString();
  final buf = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
    buf.write(digits[i]);
  }
  final sign = rounded < 0 ? '-' : '';
  final formatted = '$sign$buf';
  return withSuffix ? '$formatted FCFA' : formatted;
}

/// Montant réellement dû par le client sur une commande, après réduction
/// promo éventuelle — jamais `price` seul, qui reste 100% pour le livreur
/// (voir Order.discountAmount côté backend). C'est ce montant qu'il faut
/// afficher/encaisser (cash ou en ligne) côté client ET côté livreur ; le
/// livreur est remboursé de la différence par DEM (voir orders.service.js).
int clientChargeFor(Map<String, dynamic> order) {
  final price    = (order['price'] as num?)?.toDouble() ?? 0;
  final demFee   = (order['demFee'] as num?)?.toDouble() ?? 0;
  final discount = (order['discountAmount'] as num?)?.toDouble() ?? 0;
  return (price + demFee - discount).clamp(0, double.infinity).round();
}

/// Équivalent de [clientChargeFor] pour une tournée groupée (BatchOrder) —
/// le total persisté (`totalPrice`) est déjà net de la réduction tournée
/// (-20%, voir batch.service.js:_priceStops) mais n'inclut PAS `demFee`
/// (frais DEM sommés par arrêt, gardés à part) : jamais `totalPrice` seul.
/// Le champ "total" est utilisé côté réponse d'estimation (avant création),
/// "totalPrice" une fois la tournée créée — on accepte les deux noms.
int batchChargeFor(Map<String, dynamic> batch) {
  final total = (batch['totalPrice'] as num?)?.toDouble() ??
      (batch['total'] as num?)?.toDouble() ??
      0;
  final demFee = (batch['demFee'] as num?)?.toDouble() ?? 0;
  return (total + demFee).clamp(0, double.infinity).round();
}
