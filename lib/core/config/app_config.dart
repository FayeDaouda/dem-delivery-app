class AppConfig {
  // Injecté à la compilation via --dart-define=MAPS_API_KEY=xxx
  // En local : défini dans android/local.properties (non versionné)
  static const mapsApiKey = String.fromEnvironment('MAPS_API_KEY');
}
