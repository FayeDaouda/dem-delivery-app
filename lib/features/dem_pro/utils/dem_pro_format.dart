/// Formatage partagé de l'espace DEM Pro — remplace les implémentations
/// dupliquées (`_fmtFcfa`/`_fcfa`) présentes à l'identique dans plusieurs
/// écrans (accueil, reçu, tournées, création de commande/tournée...).
class DemProFormat {
  DemProFormat._();

  static String fcfa(num value) {
    final s = value.round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '$buf FCFA';
  }
}
