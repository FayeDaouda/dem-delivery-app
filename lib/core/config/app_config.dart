class AppConfig {
  // ⚠️  NE JAMAIS mettre la vraie clé ici.
  // Passer --dart-define=MAPS_API_KEY=<clé> à la commande de build :
  //   flutter build apk  --dart-define=MAPS_API_KEY=AIza...
  //   flutter build ipa  --dart-define=MAPS_API_KEY=AIza...
  // En debug, la clé vient aussi de --dart-define (voir launch.json / run config).
  static const mapsApiKey = String.fromEnvironment('MAPS_API_KEY', defaultValue: '');

  static const privacyPolicyUrl = 'https://dem.sn/privacy';
  static const termsUrl         = 'https://dem.sn/terms';
}
