import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/api/api_client.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../data/chef_de_flotte_repository.dart';

/// Carte en direct de la flotte — un marqueur par livreur actif ayant déjà
/// transmis sa position. Rafraîchi par sondage périodique de
/// GET /chefs-de-flotte/me/drivers/live plutôt qu'un flux socket dédié : cet
/// endpoint REST existait déjà côté serveur pour cet usage précis, et un
/// intervalle de 10s est largement suffisant pour situer une flotte sur une
/// carte (contrairement au suivi d'une course unique, qui a besoin du
/// temps réel).
class ChefDeFlotteFleetMapScreen extends StatefulWidget {
  const ChefDeFlotteFleetMapScreen({super.key});
  @override
  State<ChefDeFlotteFleetMapScreen> createState() => _State();
}

class _State extends State<ChefDeFlotteFleetMapScreen> {
  final _repo = ChefDeFlotteRepository(ApiClient.dio);
  List<Map<String, dynamic>> _drivers = [];
  bool _loading = true;
  String? _error;
  Timer? _timer;
  Map<String, dynamic>? _selected;

  // Icônes avatar générées à la volée, une par couple (initiale, état) —
  // évite de redessiner un bitmap identique à chaque rafraîchissement.
  final Map<String, BitmapDescriptor> _avatarIcons = {};

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final drivers = await _repo.getMyDriversLive();
      if (!mounted) return;
      setState(() {
        _drivers = drivers;
        _loading = false;
      });
      unawaited(_ensureIcons(drivers));
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _loading = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  String _stateOf(Map<String, dynamic> d) {
    if (d['currentOrder'] != null) return 'busy';
    if (d['isAvailable'] == true) return 'available';
    return 'offline';
  }

  String _stateLabel(String state) => switch (state) {
    'available' => 'Disponible',
    'busy' => 'En course',
    _ => 'Hors ligne',
  };

  Color _stateColor(String state) => switch (state) {
    'available' => Colors.green,
    'busy' => Colors.orange,
    _ => Colors.grey,
  };

  String _initialOf(Map<String, dynamic> d) {
    final name = (d['name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name[0].toUpperCase();
    final phone = d['phone'] as String?;
    if (phone != null && phone.isNotEmpty) {
      return phone[phone.startsWith('+') ? 1 : 0];
    }
    return '?';
  }

  /// Génère les avatars manquants (un bitmap par couple initiale/état) et
  /// les met en cache — un simple pin coloré ne dit pas qui est qui sur une
  /// flotte de plusieurs livreurs, l'initiale si.
  Future<void> _ensureIcons(List<Map<String, dynamic>> drivers) async {
    final missing = <String>{
      for (final d in drivers)
        if (!_avatarIcons.containsKey('${_initialOf(d)}|${_stateOf(d)}'))
          '${_initialOf(d)}|${_stateOf(d)}',
    };
    if (missing.isEmpty) return;
    final built = await Future.wait(
      missing.map((key) async {
        final parts = key.split('|');
        final icon = await _buildAvatarMarkerIcon(
          parts[0],
          _stateColor(parts[1]),
        );
        return MapEntry(key, icon);
      }),
    );
    if (!mounted) return;
    setState(() => _avatarIcons.addEntries(built));
  }

  /// Marqueur avatar : disque à l'initiale du livreur cerclé de la couleur
  /// de son état (disponible/en course/hors ligne), plutôt qu'un pin
  /// générique — technique canvas déjà utilisée par [RouteMarkerIcons].
  static Future<BitmapDescriptor> _buildAvatarMarkerIcon(
    String initial,
    Color ringColor,
  ) async {
    const double size = 96;
    const double c = size / 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawCircle(
      const Offset(c, c + 3),
      33,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.20)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5),
    );
    canvas.drawCircle(const Offset(c, c), 33, Paint()..color = ringColor);
    canvas.drawCircle(const Offset(c, c), 28, Paint()..color = Colors.white);
    canvas.drawCircle(
      const Offset(c, c),
      25,
      Paint()..color = AppColors.primaryMid,
    );

    final painter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: initial,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      )
      ..layout();
    painter.paint(
      canvas,
      Offset(c - painter.width / 2, c - painter.height / 2),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      width: 44,
      height: 44,
    );
  }

  /// Trace pointillée du trajet en cours — vers le point de collecte si le
  /// livreur n'a pas encore récupéré le colis, vers la livraison sinon.
  /// Ligne directe (pas d'appel Directions/OSRM) : c'est une vue d'ensemble
  /// de flotte, pas une navigation pas-à-pas, et l'appeler pour chaque
  /// livreur en course à chaque sondage de 10s coûterait cher pour rien.
  Set<Polyline> _buildPolylines(List<Map<String, dynamic>> withPosition) {
    final polylines = <Polyline>{};
    for (final d in withPosition) {
      final order = d['currentOrder'] as Map?;
      if (order == null) continue;
      final lat = (d['latitude'] as num?)?.toDouble();
      final lng = (d['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final headingToPickup = order['status'] == 'ACCEPTED';
      final targetLat = headingToPickup
          ? (order['pickupLatitude'] as num?)?.toDouble()
          : (order['deliveryLatitude'] as num?)?.toDouble();
      final targetLng = headingToPickup
          ? (order['pickupLongitude'] as num?)?.toDouble()
          : (order['deliveryLongitude'] as num?)?.toDouble();
      if (targetLat == null || targetLng == null) continue;

      polylines.add(
        Polyline(
          polylineId: PolylineId('route-${d['id']}'),
          points: [LatLng(lat, lng), LatLng(targetLat, targetLng)],
          color: AppColors.primaryMid.withValues(alpha: 0.55),
          width: 3,
          patterns: [PatternItem.dash(16), PatternItem.gap(10)],
        ),
      );
    }
    return polylines;
  }

  @override
  Widget build(BuildContext context) {
    final withPosition = _drivers
        .where((d) => d['latitude'] != null && d['longitude'] != null)
        .toList();

    final markers = <Marker>{
      for (final d in withPosition)
        Marker(
          markerId: MarkerId(d['id'] as String),
          position: LatLng(
            (d['latitude'] as num).toDouble(),
            (d['longitude'] as num).toDouble(),
          ),
          anchor: const Offset(0.5, 0.5),
          icon:
              _avatarIcons['${_initialOf(d)}|${_stateOf(d)}'] ??
              BitmapDescriptor.defaultMarkerWithHue(switch (_stateOf(d)) {
                'available' => BitmapDescriptor.hueGreen,
                'busy' => BitmapDescriptor.hueOrange,
                _ => BitmapDescriptor.hueAzure,
              }),
          onTap: () => setState(() => _selected = d),
        ),
    };

    final initTarget = withPosition.isNotEmpty
        ? LatLng(
            (withPosition.first['latitude'] as num).toDouble(),
            (withPosition.first['longitude'] as num).toDouble(),
          )
        : const LatLng(14.6937, -17.4441); // Dakar par défaut

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 20),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const Text(
                      'Carte de la flotte',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryMid,
                    ),
                  )
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.wifi_off_rounded,
                            color: Colors.grey,
                            size: 40,
                          ),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => _load(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryMid,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Réessayer'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: initTarget,
                          zoom: 12,
                        ),
                        myLocationEnabled: false,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                        markers: markers,
                        polylines: _buildPolylines(withPosition),
                        onTap: (_) => setState(() => _selected = null),
                      ),
                      if (withPosition.isEmpty)
                        Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 32),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.location_off_outlined,
                                  color: Colors.grey,
                                  size: 32,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _drivers.isEmpty
                                      ? 'Aucun livreur actif dans votre flotte.'
                                      : 'Aucun livreur actif n\'a encore transmis sa position.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // ── Légende ──────────────────────────────────────────────
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              for (final s in ['available', 'busy', 'offline'])
                                Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: _stateColor(s),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _stateLabel(s),
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      // ── Fiche livreur sélectionné ────────────────────────────
                      if (_selected != null)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: TweenAnimationBuilder<double>(
                            key: ValueKey(_selected!['id']),
                            tween: Tween(begin: 0, end: 1),
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            builder: (context, t, child) => Opacity(
                              opacity: t,
                              child: Transform.translate(
                                offset: Offset(0, (1 - t) * 24),
                                child: child,
                              ),
                            ),
                            child: _DriverInfoCard(
                              driver: _selected!,
                              state: _stateOf(_selected!),
                              stateLabel: _stateLabel(_stateOf(_selected!)),
                              stateColor: _stateColor(_stateOf(_selected!)),
                              onClose: () => setState(() => _selected = null),
                              onOpenDetail: () {
                                final id = _selected!['id'] as String;
                                setState(() => _selected = null);
                                context.push('/chef-de-flotte/drivers/$id');
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _DriverInfoCard extends StatelessWidget {
  final Map<String, dynamic> driver;
  final String state;
  final String stateLabel;
  final Color stateColor;
  final VoidCallback onClose;
  final VoidCallback onOpenDetail;
  const _DriverInfoCard({
    required this.driver,
    required this.state,
    required this.stateLabel,
    required this.stateColor,
    required this.onClose,
    required this.onOpenDetail,
  });

  @override
  Widget build(BuildContext context) {
    final name = (driver['name'] as String?)?.trim();
    final hasName = name?.isNotEmpty == true;
    final phone = driver['phone'] as String? ?? '';
    final currentOrder = driver['currentOrder'] as Map?;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primaryMid.withValues(alpha: 0.12),
                child: Text(
                  hasName
                      ? name![0].toUpperCase()
                      : (phone.isNotEmpty ? phone[0] : '?'),
                  style: const TextStyle(
                    color: AppColors.primaryMid,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Numéro toujours en repère principal, nom en dessous
                    // quand renseigné — même convention que le tableau de
                    // bord (chef_de_flotte_dashboard_screen.dart).
                    Text(
                      phone.isNotEmpty ? phone : (hasName ? name! : '—'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (hasName && phone.isNotEmpty)
                      Text(
                        name!,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: stateColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          stateLabel,
                          style: TextStyle(fontSize: 12, color: stateColor),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClose,
              ),
            ],
          ),
          if (currentOrder != null) ...[
            const Divider(height: 20),
            Row(
              children: [
                const Icon(Icons.place_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    currentOrder['deliveryAddress'] as String? ?? '—',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onOpenDetail,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryMid,
                side: const BorderSide(color: AppColors.primaryMid),
              ),
              child: const Text('Voir le détail'),
            ),
          ),
        ],
      ),
    );
  }
}
