import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';

const _accent = Color(0xFF00AECB);
const _bg = Color(0xFF0A1628);
const _bg2 = Color(0xFF0F1E36);
const _textColor = Color(0xFFE8F4F8);
const _muted = Color(0xFF6B8BAA);
const _success = Color(0xFF00E08C);
const _danger = Color(0xFFFF5C5C);
const _warning = Color(0xFFFFB830);

class GuestTrackingScreen extends StatefulWidget {
  final String orderId;
  const GuestTrackingScreen({super.key, required this.orderId});
  @override
  State<GuestTrackingScreen> createState() => _GuestTrackingScreenState();
}

class _GuestTrackingScreenState extends State<GuestTrackingScreen> {
  final _dio = Dio(BaseOptions(
    baseUrl: 'https://api.dem.sn',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  GoogleMapController? _mapCtrl;
  String? _mapStyle;
  Timer? _pollTimer;

  Map<String, dynamic>? _order;
  LatLng? _driverPos;
  bool _loading = true;
  bool _expired = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _fetchOrder();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _fetchOrder());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _mapCtrl?.dispose();
    super.dispose();
  }

  Future<void> _loadMapStyle() async {
    try {
      final style = await rootBundle.loadString('assets/map_style_waze.json');
      if (mounted) setState(() => _mapStyle = style);
    } catch (_) {}
  }

  Future<void> _fetchOrder() async {
    try {
      final res = await _dio.get('/orders/guest/${widget.orderId}');
      if (!mounted) return;
      final data = res.data as Map<String, dynamic>;
      final driver = data['driver'] as Map<String, dynamic>?;
      final lat = (driver?['latitude'] as num?)?.toDouble();
      final lng = (driver?['longitude'] as num?)?.toDouble();

      setState(() {
        _order = data;
        _loading = false;
        _expired = data['isExpired'] == true;
        if (lat != null && lng != null && lat != 0 && lng != 0) {
          _driverPos = LatLng(lat, lng);
        }
      });

      if (_driverPos != null) {
        _mapCtrl?.animateCamera(CameraUpdate.newLatLng(_driverPos!));
      }

      if (_expired) _pollTimer?.cancel();
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 404) {
        setState(() { _error = 'Commande introuvable.'; _loading = false; });
        _pollTimer?.cancel();
      } else {
        if (_order == null) setState(() { _error = 'Erreur de connexion.'; _loading = false; });
      }
    }
  }

  (String, Color, IconData) get _statusInfo {
    final s = (_order?['status'] as String? ?? '').toUpperCase();
    return switch (s) {
      'PENDING'   => ('En recherche de livreur', _warning, Icons.search),
      'ACCEPTED'  => ('Livreur en route vers le colis', _accent, Icons.two_wheeler),
      'PICKED_UP' => ('Colis récupéré — en route', _warning, Icons.local_shipping),
      'IN_TRANSIT'=> ('En cours de livraison', _accent, Icons.local_shipping),
      'DELIVERED' => ('Livraison effectuée', _success, Icons.check_circle),
      'CANCELLED' => ('Commande annulée', _danger, Icons.cancel),
      _           => ('En attente', _muted, Icons.hourglass_empty),
    };
  }

  String _short(String? addr) =>
      (addr == null || addr.isEmpty) ? '—' : addr.split(',').first.trim();

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: _bg,
        body: const Center(child: CircularProgressIndicator(color: _accent)),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: _danger, size: 48),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: _textColor, fontSize: 16)),
          ],
        )),
      );
    }

    final o = _order!;
    final pLat = (o['pickupLatitude'] as num?)?.toDouble() ?? 14.6928;
    final pLng = (o['pickupLongitude'] as num?)?.toDouble() ?? -17.4467;
    final dLat = (o['deliveryLatitude'] as num?)?.toDouble() ?? 14.6928;
    final dLng = (o['deliveryLongitude'] as num?)?.toDouble() ?? -17.4467;
    final pickup = _short(o['pickupAddress'] as String?);
    final delivery = _short(o['deliveryAddress'] as String?);
    final driver = o['driver'] as Map<String, dynamic>?;
    final driverName = driver?['name'] as String? ?? 'Livreur';
    final vehiclePlate = driver?['vehiclePlate'] as String?;
    final (statusLabel, statusColor, statusIcon) = _statusInfo;

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(pLat, pLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      Marker(
        markerId: const MarkerId('delivery'),
        position: LatLng(dLat, dLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
      if (_driverPos != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: _driverPos!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
        ),
    };

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        Positioned.fill(child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _driverPos ?? LatLng((pLat + dLat) / 2, (pLng + dLng) / 2),
            zoom: 14,
          ),
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          style: _mapStyle,
          markers: markers,
          onMapCreated: (c) {
            _mapCtrl = c;
            c.animateCamera(CameraUpdate.newLatLngBounds(
              LatLngBounds(
                southwest: LatLng(min(pLat, dLat), min(pLng, dLng)),
                northeast: LatLng(max(pLat, dLat), max(pLng, dLng)),
              ),
              80,
            ));
          },
        )),

        // Header
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 12, right: 12,
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _bg2.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Image.asset('assets/images/logo_dem.png', height: 20, errorBuilder: (_, __, ___) => const Icon(Icons.two_wheeler, color: _accent, size: 20)),
                const SizedBox(width: 8),
                const Text('Suivi DEM', style: TextStyle(color: _textColor, fontWeight: FontWeight.w700, fontSize: 14)),
              ]),
            ),
            const Spacer(),
            if (_driverPos != null)
              GestureDetector(
                onTap: () => _mapCtrl?.animateCamera(CameraUpdate.newLatLng(_driverPos!)),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: _bg2.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.my_location, color: _textColor, size: 20),
                ),
              ),
          ]),
        ),

        // Panel bas
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).padding.bottom + 20),
            decoration: BoxDecoration(
              color: _bg2,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Statut
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.25)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(statusIcon, color: statusColor, size: 18),
                  const SizedBox(width: 8),
                  Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 14)),
                ]),
              ),
              const SizedBox(height: 16),

              // Driver info
              if (driver != null && !_expired) ...[
                Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(child: Text(
                      driverName.isNotEmpty ? driverName[0].toUpperCase() : '?',
                      style: const TextStyle(color: _accent, fontWeight: FontWeight.w800, fontSize: 18),
                    )),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(driverName, style: const TextStyle(color: _textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                    if (vehiclePlate != null)
                      Text(vehiclePlate, style: const TextStyle(color: _muted, fontSize: 12)),
                  ])),
                ]),
                const SizedBox(height: 16),
              ],

              // Adresses
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF111E35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(children: [
                  Row(children: [
                    const Icon(Icons.radio_button_on, color: _success, size: 13),
                    const SizedBox(width: 10),
                    Expanded(child: Text(pickup, style: const TextStyle(color: _textColor, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                  Padding(
                    padding: const EdgeInsets.only(left: 6, top: 3, bottom: 3),
                    child: Align(alignment: Alignment.centerLeft, child: Container(width: 1.5, height: 10, color: const Color(0xFF1E3050))),
                  ),
                  Row(children: [
                    const Icon(Icons.location_on, color: _danger, size: 13),
                    const SizedBox(width: 10),
                    Expanded(child: Text(delivery, style: const TextStyle(color: _textColor, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                ]),
              ),

              if (_expired) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: _muted.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Ce suivi n\'est plus actif',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted, fontSize: 13),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}
