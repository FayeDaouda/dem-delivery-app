import 'dart:async';

import 'package:app_links/app_links.dart';

import '../router/app_router.dart';

/// Écoute le lien personnalisé dem://commander/:id — schéma déjà déclaré
/// dans AndroidManifest.xml/Info.plist mais jamais consommé côté Dart
/// jusqu'ici (la page publique dem.sn/commander/:id le propose désormais
/// dans une bannière "Ouvrir dans l'app" sur mobile). Route directement
/// vers la boutique publique in-app (StorefrontScreen), sans passer par un
/// navigateur.
class DeepLinkService {
  static final _appLinks = AppLinks();
  static StreamSubscription<Uri>? _sub;

  static Future<void> init() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (_) {}
    _sub = _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
  }

  static void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  // dem://commander/abc123 — pour un schéma personnalisé, "commander" est
  // analysé comme le host (pas le premier segment de chemin), abc123 comme
  // pathSegments.first.
  static void _handle(Uri uri) {
    if (uri.host == 'commander' && uri.pathSegments.isNotEmpty) {
      appRouter.go('/commander/${uri.pathSegments.first}');
    }
  }
}
