import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../theme/map_theme_provider.dart';
import '../../features/home_driver/navigation/map_theme.dart';

class MapStyleService {
  /// Charge le style depuis le provider (nuit ou jour).
  static Future<String> load(WidgetRef ref) async {
    final isNight = ref.read(mapNightProvider);
    return rootBundle.loadString(MapTheme.styleAssetFor(isNight));
  }

  /// Applique directement le style sur un controller existant.
  static Future<void> apply(GoogleMapController controller, WidgetRef ref) async {
    final style = await load(ref);
    await controller.setMapStyle(style);
  }

  /// Écoute les changements de thème et recharge le style automatiquement.
  /// À appeler dans build() des écrans ConsumerStatefulWidget.
  static void listen(
    WidgetRef ref,
    GoogleMapController? Function() getController,
    void Function(String style) onStyleChanged,
  ) {
    ref.listen<bool>(mapNightProvider, (_, isNight) async {
      final style = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
      final ctrl = getController();
      if (ctrl != null) await ctrl.setMapStyle(style);
      onStyleChanged(style);
    });
  }
}
