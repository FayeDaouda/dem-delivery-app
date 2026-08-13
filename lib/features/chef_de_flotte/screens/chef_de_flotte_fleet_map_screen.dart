import 'dart:async';

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

  double _hueOf(String state) => switch (state) {
    'available' => BitmapDescriptor.hueGreen,
    'busy' => BitmapDescriptor.hueOrange,
    _ => BitmapDescriptor.hueAzure,
  };

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
          icon: BitmapDescriptor.defaultMarkerWithHue(_hueOf(_stateOf(d))),
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
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        title: const Text('Carte de la flotte'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryMid),
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
                    Text(
                      hasName ? name! : phone,
                      style: const TextStyle(fontWeight: FontWeight.w700),
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
