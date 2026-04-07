/// Paramètres de configuration injectés à la compilation.
/// Lancer avec : flutter run --dart-define=MAPS_API_KEY=VOTRE_CLE
/// Sans cette option, la route réelle sera remplacée par une ligne droite.
class AppConfig {
  static const mapsApiKey = String.fromEnvironment('MAPS_API_KEY', defaultValue: '');
}
