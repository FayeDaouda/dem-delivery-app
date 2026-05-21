import 'package:dio/dio.dart';

/// Erreur métier — équivalent de AppError côté backend.
/// Toutes les erreurs de l'app remontent via cette classe.
class AppException implements Exception {
  final String message;
  final int? statusCode;

  const AppException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

/// Convertit n'importe quelle exception en message lisible par l'utilisateur.
/// À utiliser partout à la place de `e.toString()`.
String friendlyError(Object e) {
  if (e is AppException) return e.message;
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final msg = data['message'];
      if (msg is String && msg.isNotEmpty) return msg;
    }
    return switch (e.response?.statusCode) {
      400 => 'Données invalides. Vérifiez vos informations.',
      401 => 'Session expirée. Veuillez vous reconnecter.',
      403 => 'Accès refusé.',
      404 => 'Ressource introuvable.',
      409 => 'Un conflit est survenu. Réessayez.',
      429 => 'Trop de tentatives. Réessayez plus tard.',
      500 || 502 || 503 => 'Erreur serveur. Réessayez plus tard.',
      _ => _dioTypeMessage(e.type),
    };
  }
  return 'Une erreur est survenue.';
}

String _dioTypeMessage(DioExceptionType type) => switch (type) {
  DioExceptionType.connectionTimeout ||
  DioExceptionType.receiveTimeout    ||
  DioExceptionType.sendTimeout       => 'Délai dépassé. Vérifiez votre connexion.',
  DioExceptionType.connectionError   => 'Pas de connexion internet.',
  _                                  => 'Une erreur est survenue.',
};
