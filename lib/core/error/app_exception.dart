/// Erreur métier — équivalent de AppError côté backend.
/// Toutes les erreurs de l'app remontent via cette classe.
class AppException implements Exception {
  final String message;
  final int? statusCode;

  const AppException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}
