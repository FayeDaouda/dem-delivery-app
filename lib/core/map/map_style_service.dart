import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/map_theme_provider.dart';
import '../../features/home_driver/navigation/map_theme.dart';

class MapStyleService {
  static Future<String> load(WidgetRef ref) async {
    final isNight = ref.read(mapNightProvider);
    return rootBundle.loadString(MapTheme.styleAssetFor(isNight));
  }

  /// Écoute les changements de thème et appelle [onStyleChanged] pour rebuild.
  /// Le style est passé via GoogleMap(style: ...) — setMapStyle est déprécié.
  static void listen(
    WidgetRef ref,
    void Function(String style) onStyleChanged,
  ) {
    ref.listen<bool>(mapNightProvider, (_, isNight) async {
      final style = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
      onStyleChanged(style);
    });
  }
}
