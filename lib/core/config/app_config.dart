class AppConfig {
  static const mapsApiKey = String.fromEnvironment(
    'MAPS_API_KEY',
    defaultValue: 'AIzaSyB2RJfO_3UXw5NqTm29UU1vM6wASW_Lfjk',
  );

  static const privacyPolicyUrl = 'https://dem.sn/privacy';
  static const termsUrl         = 'https://dem.sn/terms';
}
