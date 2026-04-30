import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/config/app_config.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';
import '../deliveries/data/orders_repository.dart';
import '../home_driver/navigation/map_theme.dart';

// ─── Heights par step ────────────────────────────────────────────────────────
const _kPanelHeights = [180.0, 290.0, 310.0, 260.0]; // step 0, 1, 2, 3

class OrderCreateScreen extends StatefulWidget {
  final String orderType;
  const OrderCreateScreen({super.key, this.orderType = 'DELIVERY'});

  @override
  State<OrderCreateScreen> createState() => _OrderCreateScreenState();
}

class _OrderCreateScreenState extends State<OrderCreateScreen> {
  final _repo = OrdersRepository();

  // ── Constants ────────────────────────────────────────────────────────────
  static const double _baseFare = 500;
  static const double _pricePerKm = 200;
  static const LatLng _dakar = LatLng(14.6937, -17.4441);

  // ── Step wizard ──────────────────────────────────────────────────────────
  int _step = 0; // 0=Trajet, 1=Contacts, 2=Résumé
  late final PageController _pageCtrl;

  // ── Map ──────────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  String? _mapStyle;
  bool _isMapMoving = false;
  LatLng _currentCameraPos = _dakar;

  // ── Placement mode ───────────────────────────────────────────────────────
  bool _isSelectingPickup = true;
  bool _isMapPlacementMode = false;

  // ── Addresses ────────────────────────────────────────────────────────────
  final _pickupCtrl   = TextEditingController();
  final _deliveryCtrl = TextEditingController();
  double? _pickupLat, _pickupLng;
  double? _deliveryLat, _deliveryLng;

  // ── Contacts ─────────────────────────────────────────────────────────────
  final _senderNameCtrl    = TextEditingController();
  final _senderPhoneCtrl   = TextEditingController();
  final _receiverNameCtrl  = TextEditingController();
  final _receiverPhoneCtrl = TextEditingController();
  final _descriptionCtrl   = TextEditingController();

  // ── Autocomplete ─────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _suggestions = [];
  bool _isSearching = false;
  Timer? _searchDebounce;

  // ── Pricing ──────────────────────────────────────────────────────────────
  double _surgeMultiplier = 1.0;
  double? _estimatedPrice;
  bool _loadingSurge = false;
  bool _loadingGps   = false;
  bool _submitting   = false;
  Timer? _surgeDebounce;
  List<LatLng> _routePoints = [];
  Map<String, dynamic>? _currentUser;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _loadMapStyle();
    _fetchGpsInit();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await AuthStorage.getUser();
    if (mounted) setState(() => _currentUser = user);
  }

  void _fillMe(TextEditingController nameCtrl, TextEditingController phoneCtrl) {
    if (_currentUser != null) {
      nameCtrl.text = _currentUser!['name'] ?? _currentUser!['firstName'] ?? '';
      phoneCtrl.text = (_currentUser!['phone'] ?? '').replaceFirst('+221', '');
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _searchDebounce?.cancel();
    _surgeDebounce?.cancel();
    _pickupCtrl.dispose();
    _deliveryCtrl.dispose();
    _senderNameCtrl.dispose();
    _senderPhoneCtrl.dispose();
    _receiverNameCtrl.dispose();
    _receiverPhoneCtrl.dispose();
    _descriptionCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // ── Map style ────────────────────────────────────────────────────────────
  Future<void> _loadMapStyle() async {
    final style = await rootBundle.loadString(MapTheme.styleAsset);
    if (mounted) setState(() => _mapStyle = style);
  }

  // ── GPS ──────────────────────────────────────────────────────────────────
  Future<void> _fetchGpsInit() async {
    setState(() => _loadingGps = true);
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) await Geolocator.requestPermission();
      final pos = await Geolocator.getCurrentPosition();
      final ll = LatLng(pos.latitude, pos.longitude);
      _currentCameraPos = ll;
      _centerMap(ll);
      _pickupLat = ll.latitude;
      _pickupLng = ll.longitude;
      _reverseGeocode(ll, forPickup: true);
    } catch (_) {
      // fallback Dakar
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  void _centerMap(LatLng pos) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: pos, zoom: 17, tilt: 55)),
    );
  }

  // ── Reverse geocoding ────────────────────────────────────────────────────
  Future<void> _reverseGeocode(LatLng pos, {required bool forPickup}) async {
    try {
      final marks = await geo.placemarkFromCoordinates(pos.latitude, pos.longitude)
          .timeout(const Duration(seconds: 5));
      if (marks.isNotEmpty && mounted) {
        final p = marks.first;
        final street = p.street ?? p.name ?? '';
        final local  = p.subLocality ?? p.locality ?? '';
        final addr   = street.isNotEmpty ? '$street, $local' : local;
        setState(() {
          if (forPickup) {
            _pickupCtrl.text = addr.isNotEmpty ? addr : '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
          } else {
            _deliveryCtrl.text = addr.isNotEmpty ? addr : '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
          }
        });
      }
    } catch (_) {}
  }

  // ── Confirm map placement ─────────────────────────────────────────────────
  Future<void> _confirmPlacement() async {
    setState(() {
      _isMapPlacementMode = false;
      if (_isSelectingPickup) {
        _pickupLat = _currentCameraPos.latitude;
        _pickupLng = _currentCameraPos.longitude;
      } else {
        _deliveryLat = _currentCameraPos.latitude;
        _deliveryLng = _currentCameraPos.longitude;
      }
    });
    _updateEstimate();
    await _reverseGeocode(_currentCameraPos, forPickup: _isSelectingPickup);
  }

  // ── Autocomplete ─────────────────────────────────────────────────────────
  void _onAddressChanged(String query, {required bool forPickup}) {
    setState(() => _isSelectingPickup = forPickup);
    _searchDebounce?.cancel();
    if (query.trim().length < 3) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 600), () async {
      setState(() => _isSearching = true);
      try {
        final dio = Dio(BaseOptions(headers: {'User-Agent': 'com.dem.app/1.0'}));
        final res = await dio.get(
          'https://nominatim.openstreetmap.org/search',
          queryParameters: {'q': query, 'format': 'json', 'limit': 5, 'countrycodes': 'sn'},
        );
        if (mounted) {
          setState(() {
            _suggestions = List<Map<String, dynamic>>.from(res.data);
            _isSearching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  Future<void> _selectSuggestion(Map<String, dynamic> place) async {
    final lat = double.tryParse(place['lat']?.toString() ?? '');
    final lng = double.tryParse(place['lon']?.toString() ?? '');
    if (lat == null || lng == null) return;
    final name = (place['name'] as String?) ?? place['display_name'] as String? ?? '';
    FocusScope.of(context).unfocus();
    setState(() {
      _suggestions = [];
      if (_isSelectingPickup) {
        _pickupLat = lat; _pickupLng = lng;
        _pickupCtrl.text = name;
      } else {
        _deliveryLat = lat; _deliveryLng = lng;
        _deliveryCtrl.text = name;
      }
    });
    _centerMap(LatLng(lat, lng));
    _updateEstimate();
  }

  // ── Pricing ──────────────────────────────────────────────────────────────
  void _updateEstimate() {
    if (_pickupLat == null || _deliveryLat == null) return;
    _surgeDebounce?.cancel();
    _surgeDebounce = Timer(const Duration(milliseconds: 800), _computeEstimate);
  }

  Future<Map<String, dynamic>?> _fetchRouteAndDistance(
      double lat1, double lng1, double lat2, double lng2) async {
    // Essaie Google Directions en premier (clé déjà configurée)
    final googleResult = await _fetchGoogleDirections(lat1, lng1, lat2, lng2);
    if (googleResult != null) return googleResult;
    // Fallback OSRM si la clé n'est pas dispo en Dart
    return _fetchOsrmRoute(lat1, lng1, lat2, lng2);
  }

  Future<Map<String, dynamic>?> _fetchGoogleDirections(
      double lat1, double lng1, double lat2, double lng2) async {
    final key = AppConfig.mapsApiKey;
    if (key.isEmpty) return null;
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8)));
      final res = await dio.get(
        'https://maps.googleapis.com/maps/api/directions/json',
        queryParameters: {
          'origin': '$lat1,$lng1',
          'destination': '$lat2,$lng2',
          'key': key,
        },
      );
      if (res.statusCode == 200 && res.data['status'] == 'OK') {
        final route = (res.data['routes'] as List).first as Map<String, dynamic>;
        final legs  = route['legs'] as List;
        double distM = 0;
        for (final leg in legs) {
          distM += ((leg['distance'] as Map)['value'] as num).toDouble();
        }
        final encoded = route['overview_polyline']['points'] as String;
        return {'distance': distM / 1000.0, 'points': _decodePolyline(encoded)};
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _fetchOsrmRoute(
      double lat1, double lng1, double lat2, double lng2) async {
    try {
      final dio = Dio(BaseOptions(
        headers: {'User-Agent': 'DEM-App/1.0'},
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ));
      final res = await dio.get(
        'https://router.project-osrm.org/route/v1/driving/$lng1,$lat1;$lng2,$lat2',
        queryParameters: {'overview': 'full', 'geometries': 'geojson'},
      );
      if (res.statusCode == 200) {
        final routes = res.data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes[0] as Map<String, dynamic>;
          final distance = (route['distance'] as num) / 1000.0;
          final coords = (route['geometry']['coordinates'] as List);
          final points = coords.map((c) {
            final coord = c as List;
            return LatLng((coord[1] as num).toDouble(), (coord[0] as num).toDouble());
          }).toList();
          return {'distance': distance, 'points': points};
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _computeEstimate() async {
    if (_pickupLat == null || _deliveryLat == null) return;
    setState(() => _loadingSurge = true);
    try {
      final surge = await _repo.getSurgeMultiplier(_pickupLat!, _pickupLng!);
      
      final routeData = await _fetchRouteAndDistance(_pickupLat!, _pickupLng!, _deliveryLat!, _deliveryLng!);
      double dist = 0.0;
      
      if (routeData != null && mounted) {
        dist = routeData['distance'] as double;
        setState(() => _routePoints = routeData['points'] as List<LatLng>);
      } else {
        dist = _haversineKm(_pickupLat!, _pickupLng!, _deliveryLat!, _deliveryLng!);
        if (mounted) setState(() => _routePoints = [LatLng(_pickupLat!, _pickupLng!), LatLng(_deliveryLat!, _deliveryLng!)]);
      }

      final price = (_baseFare + dist * _pricePerKm) * surge;
      if (mounted) setState(() { _surgeMultiplier = surge; _estimatedPrice = price.roundToDouble(); _loadingSurge = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingSurge = false);
    }
  }

  // Décode le format encoded polyline de Google Maps
  List<LatLng> _decodePolyline(String encoded) {
    final result = <LatLng>[];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, res = 0;
      do { b = encoded.codeUnitAt(index++) - 63; res |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
      lat += (res & 1) != 0 ? ~(res >> 1) : (res >> 1);
      shift = 0; res = 0;
      do { b = encoded.codeUnitAt(index++) - 63; res |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
      lng += (res & 1) != 0 ? ~(res >> 1) : (res >> 1);
      result.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return result;
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  // ── Step navigation ───────────────────────────────────────────────────────
  bool get _routeComplete => _pickupLat != null && _deliveryLat != null;

  void _goStep(int step) {
    setState(() => _step = step);
    _pageCtrl.animateToPage(step,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  // ── Contacts ─────────────────────────────────────────────────────────────
  Future<void> _pickContact({
    required TextEditingController nameCtrl,
    required TextEditingController phoneCtrl,
  }) async {
    final status = await Permission.contacts.status;
    bool granted = status.isGranted || status.isLimited;
    if (!granted) {
      final result = await Permission.contacts.request();
      granted = result.isGranted || result.isLimited;
    }
    if (!granted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Accès aux contacts refusé'),
        action: status.isPermanentlyDenied
            ? SnackBarAction(label: 'Paramètres', onPressed: openAppSettings)
            : null,
      ));
      return;
    }
    final contacts = await FlutterContacts.getAll(
      properties: {ContactProperty.name, ContactProperty.phone},
    );
    if (!mounted) return;
    _showContactPicker(contacts, nameCtrl: nameCtrl, phoneCtrl: phoneCtrl);
  }

  void _showContactPicker(List<Contact> contacts,
      {required TextEditingController nameCtrl,
      required TextEditingController phoneCtrl}) {
    String q = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSB) {
          final filtered = contacts.where((c) =>
              q.isEmpty || (c.displayName ?? '').toLowerCase().contains(q.toLowerCase())).toList();
          return DraggableScrollableSheet(
            initialChildSize: 0.65, maxChildSize: 0.95, minChildSize: 0.4,
            builder: (_, sc) => Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(children: [
                const SizedBox(height: 12),
                Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 12),
                const Text('Choisir un contact',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Rechercher...',
                      prefixIcon: const Icon(Icons.search),
                      fillColor: AppColors.card, filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (v) => setSB(() => q = v),
                  ),
                ),
                Divider(color: AppColors.textSecondary.withValues(alpha: 0.2), height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: sc,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      final phoneObj = c.phones.isNotEmpty ? c.phones.first : null;
                      if (phoneObj == null) return const SizedBox.shrink();
                      final cleaned = phoneObj.number.replaceAll(RegExp(r'[\s\-\(\)]'), '').replaceFirst('+221', '');
                      final name = c.displayName ?? 'Contact';
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        subtitle: Text(cleaned, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        onTap: () {
                          Navigator.pop(ctx);
                          nameCtrl.text = name;
                          phoneCtrl.text = cleaned;
                        },
                      );
                    },
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (_pickupCtrl.text.trim().isEmpty) {
      _pickupCtrl.text = '${_pickupLat!.toStringAsFixed(4)}, ${_pickupLng!.toStringAsFixed(4)}';
    }
    if (_deliveryCtrl.text.trim().isEmpty) {
      _deliveryCtrl.text = '${_deliveryLat!.toStringAsFixed(4)}, ${_deliveryLng!.toStringAsFixed(4)}';
    }
    setState(() => _submitting = true);
    try {
      final order = await _repo.createOrder({
        'orderType': widget.orderType,
        'pickupAddress': _pickupCtrl.text.trim(),
        'pickupLatitude': _pickupLat,
        'pickupLongitude': _pickupLng,
        'deliveryAddress': _deliveryCtrl.text.trim(),
        'deliveryLatitude': _deliveryLat,
        'deliveryLongitude': _deliveryLng,
        if (_senderNameCtrl.text.trim().isNotEmpty)   'senderName':  _senderNameCtrl.text.trim(),
        if (_senderPhoneCtrl.text.trim().isNotEmpty)  'senderPhone': '+221${_senderPhoneCtrl.text.trim()}',
        if (_receiverNameCtrl.text.trim().isNotEmpty) 'receiverName': _receiverNameCtrl.text.trim(),
        if (_receiverPhoneCtrl.text.trim().isNotEmpty)'receiverPhone':'+221${_receiverPhoneCtrl.text.trim()}',
        if (widget.orderType == 'DELIVERY')
          'description': _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
        if (_estimatedPrice != null) 'price': _estimatedPrice,
      });
      
      // Assure que le prix affiché sur la confirmation est exactement le même que l'estimé
      if (_estimatedPrice != null) {
        order['price'] = _estimatedPrice;
      }
      
      if (mounted) context.pushReplacement('/orders/confirmation', extra: order);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final panelH = _isMapPlacementMode ? 90.0 : _kPanelHeights[_step];

    // Polyline + inactive markers
    Set<Polyline> polylines = {};
    Set<Marker> markers    = {};
    if (_pickupLat != null && _deliveryLat != null) {
      polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        points: _routePoints.isNotEmpty ? _routePoints : [LatLng(_pickupLat!, _pickupLng!), LatLng(_deliveryLat!, _deliveryLng!)],
        color: AppColors.primary, width: 4,
      ));
    }
    if (_pickupLat != null && (!_isSelectingPickup || !_isMapPlacementMode)) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(_pickupLat!, _pickupLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ));
    }
    if (_deliveryLat != null && (_isSelectingPickup || !_isMapPlacementMode)) {
      markers.add(Marker(
        markerId: const MarkerId('delivery'),
        position: LatLng(_deliveryLat!, _deliveryLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ));
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(children: [

        // ── MAP ────────────────────────────────────────────────────────────
        SizedBox.expand(
          child: GoogleMap(
            initialCameraPosition: const CameraPosition(target: _dakar, zoom: 17, tilt: 55),
            onMapCreated: (c) => _mapController = c,
            style: _mapStyle,
            onTap: (_) => FocusScope.of(context).unfocus(),
            onCameraMoveStarted: () => setState(() => _isMapMoving = true),
            onCameraMove: (p) => _currentCameraPos = p.target,
            onCameraIdle: () => setState(() => _isMapMoving = false),
            polylines: polylines,
            markers: markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            buildingsEnabled: true,
          ),
        ),

        // ── CENTER PIN (placement mode only) ───────────────────────────────
        if (_isMapPlacementMode)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 35),
              child: AnimatedScale(
                scale: _isMapMoving ? 1.15 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: _FloatingPin(
                  color: _isSelectingPickup ? AppColors.success : AppColors.error,
                ),
              ),
            ),
          ),

        // ── RECENTER BTN ───────────────────────────────────────────────────
        Positioned(
          right: 16,
          bottom: panelH + 16,
          child: _FloatingBtn(
            icon: _loadingGps ? null : Icons.my_location,
            loading: _loadingGps,
            onTap: _fetchGpsInit,
          ),
        ),

        // ── TOP BAR ────────────────────────────────────────────────────────
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                _TopBar(
                  title: widget.orderType == 'RIDE' ? 'Transport' : 'Livraison',
                  step: _step,
                  onBack: () {
                    if (_step > 0) {
                      _goStep(_step - 1);
                    } else {
                      Navigator.pop(context);
                    }
                  },
                ),
                const SizedBox(height: 8),

                // Search fields (step 0 only, not in placement mode)
                if (_step == 0) ...[
                  _AddressField(
                    controller: _pickupCtrl,
                    hint: 'Point de départ...',
                    dotColor: AppColors.success,
                    active: _isSelectingPickup && !_isMapPlacementMode,
                    onTap: () => setState(() { _isSelectingPickup = true; _isMapPlacementMode = false; }),
                    onChanged: (v) => _onAddressChanged(v, forPickup: true),
                    onMapTap: () {
                      FocusScope.of(context).unfocus();
                      setState(() { _isSelectingPickup = true; _isMapPlacementMode = true; });
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    child: Row(children: [
                      Container(width: 2, height: 16, color: AppColors.textSecondary.withValues(alpha: 0.3)),
                    ]),
                  ),
                  _AddressField(
                    controller: _deliveryCtrl,
                    hint: 'Destination...',
                    dotColor: AppColors.error,
                    active: !_isSelectingPickup && !_isMapPlacementMode,
                    onTap: () => setState(() { _isSelectingPickup = false; _isMapPlacementMode = false; }),
                    onChanged: (v) => _onAddressChanged(v, forPickup: false),
                    onMapTap: () {
                      FocusScope.of(context).unfocus();
                      setState(() { _isSelectingPickup = false; _isMapPlacementMode = true; });
                    },
                  ),

                  // Autocomplete dropdown
                  if (_isSearching || _suggestions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _AutocompleteDropdown(
                      suggestions: _suggestions,
                      loading: _isSearching,
                      onSelect: _selectSuggestion,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),

        // ── BOTTOM PANEL ───────────────────────────────────────────────────
        Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOut,
            margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            decoration: BoxDecoration(
              gradient: AppColors.gradientSplash,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, -4))],
            ),
            child: SafeArea(
              top: false,
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                const SizedBox(height: 8),
                Center(child: Container(width: 36, height: 3, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 4),

                // Content via PageView (non scrollable)
                SizedBox(
                  height: panelH - 20,
                  child: _isMapPlacementMode
                      ? _PlacementConfirmPanel(
                          isPickup: _isSelectingPickup,
                          onConfirm: _confirmPlacement,
                        )
                      : PageView(
                          controller: _pageCtrl,
                          physics: const NeverScrollableScrollPhysics(),
                          onPageChanged: (i) => setState(() => _step = i),
                          children: [
                            _Step0Panel(
                              routeComplete: _routeComplete,
                              onNext: () => _goStep(1),
                            ),
                            _Step1Panel(
                              orderType: widget.orderType,
                              nameCtrl: _senderNameCtrl,
                              phoneCtrl: _senderPhoneCtrl,
                              onPickContact: () => _pickContact(nameCtrl: _senderNameCtrl, phoneCtrl: _senderPhoneCtrl),
                              onPickMe: () => _fillMe(_senderNameCtrl, _senderPhoneCtrl),
                              onNext: () => _goStep(2),
                            ),
                            _Step2Panel(
                              orderType: widget.orderType,
                              nameCtrl: _receiverNameCtrl,
                              phoneCtrl: _receiverPhoneCtrl,
                              descriptionCtrl: _descriptionCtrl,
                              onPickContact: () => _pickContact(nameCtrl: _receiverNameCtrl, phoneCtrl: _receiverPhoneCtrl),
                              onPickMe: () => _fillMe(_receiverNameCtrl, _receiverPhoneCtrl),
                              onNext: () {
                                _updateEstimate();
                                _goStep(3);
                              },
                            ),
                            _Step3Panel(
                              pickupLabel: _pickupCtrl.text.isNotEmpty ? _pickupCtrl.text : 'Départ',
                              deliveryLabel: _deliveryCtrl.text.isNotEmpty ? _deliveryCtrl.text : 'Destination',
                              estimatedPrice: _estimatedPrice,
                              surgeMultiplier: _surgeMultiplier,
                              loadingSurge: _loadingSurge,
                              submitting: _submitting,
                              canSubmit: _routeComplete,
                              onSubmit: _submit,
                            ),
                          ],
                        ),
                ),
              ],
            ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String title;
  final int step;
  final VoidCallback onBack;
  const _TopBar({required this.title, required this.step, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: AppColors.gradientSplash,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 12)],
      ),
      child: Row(children: [
        GestureDetector(
          onTap: onBack,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary, size: 14),
          ),
        ),
        const SizedBox(width: 12),
        Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
        const Spacer(),
        // Step dots
        Row(children: List.generate(4, (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.only(left: 4),
          width: i == step ? 20 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: i == step ? AppColors.primary : AppColors.card,
            borderRadius: BorderRadius.circular(3),
          ),
        ))),
      ]),
    );
  }
}

class _AddressField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final Color dotColor;
  final bool active;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;
  final VoidCallback onMapTap;

  const _AddressField({
    required this.controller, required this.hint, required this.dotColor,
    required this.active, required this.onTap, required this.onChanged, required this.onMapTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: active
              ? dotColor.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? dotColor.withValues(alpha: 0.85) : Colors.white.withValues(alpha: 0.06),
            width: active ? 1.4 : 1.0,
          ),
          boxShadow: active
              ? [BoxShadow(color: dotColor.withValues(alpha: 0.20), blurRadius: 20, spreadRadius: 0)]
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6)],
        ),
        child: Row(children: [
          const SizedBox(width: 12),
          active
              ? _PulsingDot(color: dotColor)
              : Container(width: 10, height: 10, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 13),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                isDense: true,
                fillColor: Colors.transparent,
                filled: true,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.map_outlined, color: Colors.white.withValues(alpha: 0.80), size: 18),
            onPressed: onMapTap,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            constraints: const BoxConstraints(),
          ),
        ]),
      ),
    );
  }
}

// ── Dot vert pulsé ────────────────────────────────────────────────────────────
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.4 + 0.3 * _ctrl.value),
              blurRadius: 8 + 6 * _ctrl.value,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pin flottant (mode placement carte) ───────────────────────────────────────
class _FloatingPin extends StatefulWidget {
  final Color color;
  const _FloatingPin({required this.color});

  @override
  State<_FloatingPin> createState() => _FloatingPinState();
}

class _FloatingPinState extends State<_FloatingPin> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _floatAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))
      ..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: 0, end: -6).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _floatAnim,
      builder: (_, _) => Transform.translate(
        offset: Offset(0, _floatAnim.value),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: -pi / 4,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomRight: Radius.circular(18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.5),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Transform.rotate(
                    angle: pi / 4,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Color(0xFF080D1A),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, _) => Container(
                width: 18,
                height: 6,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.25 + 0.15 * _ctrl.value),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutocompleteDropdown extends StatelessWidget {
  final List<Map<String, dynamic>> suggestions;
  final bool loading;
  final ValueChanged<Map<String, dynamic>> onSelect;
  const _AutocompleteDropdown({required this.suggestions, required this.loading, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        gradient: AppColors.gradientSplash,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 16)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: loading
            ? const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
            : ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: suggestions.length,
                separatorBuilder: (context, idx) => Divider(height: 1, color: Colors.white.withValues(alpha: 0.15)),
                itemBuilder: (_, i) {
                  final p = suggestions[i];
                  final name = p['name']?.toString() ?? '';
                  final sub  = (p['display_name']?.toString() ?? '').replaceAll('$name, ', '');
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.place_outlined, color: Colors.white.withValues(alpha: 0.80), size: 18),
                    title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: sub.isNotEmpty ? Text(sub, style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                    onTap: () => onSelect(p),
                  );
                },
              ),
      ),
    );
  }
}

class _FloatingBtn extends StatelessWidget {
  final IconData? icon;
  final bool loading;
  final VoidCallback onTap;
  const _FloatingBtn({required this.icon, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: AppColors.surface, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8)],
        ),
        child: loading
            ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
            : Icon(icon, color: AppColors.primary, size: 20),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Panels de chaque step
// ─────────────────────────────────────────────────────────────────────────────

class _PlacementConfirmPanel extends StatelessWidget {
  final bool isPickup;
  final VoidCallback onConfirm;
  const _PlacementConfirmPanel({required this.isPickup, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final color = isPickup ? AppColors.success : AppColors.error;
    final label = isPickup ? 'Valider ce point de départ' : 'Valider cette destination';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: onConfirm,
          icon: const Icon(Icons.check_circle_outline, size: 20),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }
}

class _Step0Panel extends StatelessWidget {
  final bool routeComplete;
  final VoidCallback onNext;
  const _Step0Panel({required this.routeComplete, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Définissez votre trajet',
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Utiliser les champs de recherche ou le bouton 🗺 pour placer un point sur la carte.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.70), fontSize: 11), maxLines: 2),
          const Spacer(),
          _NextButton(
            label: 'Suivant — Contacts',
            icon: Icons.arrow_forward,
            onTap: routeComplete ? onNext : null,
          ),
        ],
      ),
    );
  }
}

class _Step1Panel extends StatelessWidget {
  final String orderType;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final VoidCallback onPickContact;
  final VoidCallback? onPickMe;
  final VoidCallback onNext;

  const _Step1Panel({
    required this.orderType,
    required this.nameCtrl, required this.phoneCtrl,
    required this.onPickContact, this.onPickMe,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: [
          _ContactMini(
            label: orderType == 'RIDE' ? 'Passager' : 'Expéditeur',
            dotColor: AppColors.success,
            nameCtrl: nameCtrl,
            phoneCtrl: phoneCtrl,
            onPick: onPickContact,
            onPickMe: onPickMe,
          ),
          const Spacer(),
          _NextButton(
            label: 'Suivant — Destinataire',
            icon: Icons.arrow_forward,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

class _Step2Panel extends StatelessWidget {
  final String orderType;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController descriptionCtrl;
  final VoidCallback onPickContact;
  final VoidCallback? onPickMe;
  final VoidCallback onNext;

  const _Step2Panel({
    required this.orderType,
    required this.nameCtrl, required this.phoneCtrl,
    required this.descriptionCtrl,
    required this.onPickContact, this.onPickMe,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: [
          _ContactMini(
            label: orderType == 'RIDE' ? 'Destination' : 'Destinataire',
            dotColor: AppColors.error,
            nameCtrl: nameCtrl,
            phoneCtrl: phoneCtrl,
            onPick: onPickContact,
            onPickMe: onPickMe,
          ),
          if (orderType == 'DELIVERY') ...[
            const SizedBox(height: 12),
            TextField(
              controller: descriptionCtrl,
              style: const TextStyle(fontSize: 14, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Description du colis (optionnel)...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.50), fontSize: 14),
                fillColor: Colors.white.withValues(alpha: 0.10), filled: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                isDense: true,
              ),
            ),
          ],
          const SizedBox(height: 16),
          _NextButton(
            label: 'Suivant — Résumé',
            icon: Icons.arrow_forward,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

class _ContactMini extends StatelessWidget {
  final String label;
  final Color dotColor;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final VoidCallback onPick;
  final VoidCallback? onPickMe;
  const _ContactMini({required this.label, required this.dotColor, required this.nameCtrl, required this.phoneCtrl, required this.onPick, this.onPickMe});

  @override
  Widget build(BuildContext context) {
    // Vert vif visible sur fond cyan/bleu foncé
    final visibleDot = dotColor == AppColors.success ? const Color(0xFF69F0AE) : dotColor;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: visibleDot.withValues(alpha: 0.85), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: visibleDot, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: visibleDot, fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (onPickMe != null)
            GestureDetector(
              onTap: onPickMe,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.20), borderRadius: BorderRadius.circular(8)),
                child: const Text('Moi', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ),
          GestureDetector(
            onTap: onPick,
            child: Icon(Icons.contacts_rounded, color: Colors.white.withValues(alpha: 0.90), size: 26),
          ),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: nameCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Nom',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 14),
            fillColor: Colors.white.withValues(alpha: 0.10), filled: true, isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: phoneCtrl,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Téléphone',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 14),
            prefixText: '+221 ',
            prefixStyle: TextStyle(color: visibleDot, fontWeight: FontWeight.w700, fontSize: 14),
            fillColor: Colors.white.withValues(alpha: 0.10), filled: true, isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
      ]),
    );
  }
}

class _Step3Panel extends StatelessWidget {
  final String pickupLabel;
  final String deliveryLabel;
  final double? estimatedPrice;
  final double surgeMultiplier;
  final bool loadingSurge;
  final bool submitting;
  final bool canSubmit;
  final VoidCallback onSubmit;

  const _Step3Panel({
    required this.pickupLabel, required this.deliveryLabel,
    required this.estimatedPrice, required this.surgeMultiplier,
    required this.loadingSurge, required this.submitting,
    required this.canSubmit, required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(children: [
        // Route recap
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _RouteRow(icon: Icons.circle, color: AppColors.success, text: pickupLabel),
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Container(width: 2, height: 14, color: AppColors.textSecondary.withValues(alpha: 0.3)),
            ),
            _RouteRow(icon: Icons.location_on, color: AppColors.error, text: deliveryLabel),
          ]),
        ),
        const SizedBox(height: 10),
        // Price row
        Row(children: [
          const Text('Prix estimé', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const Spacer(),
          if (loadingSurge)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
          else if (estimatedPrice != null) ...[
            if (surgeMultiplier > 1.0) ...[
              const Icon(Icons.flash_on, color: Color(0xFFFF9800), size: 14),
              const SizedBox(width: 4),
            ],
            Text('${estimatedPrice!.toInt()} FCFA',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
          ] else
            const Text('—', style: TextStyle(color: AppColors.textSecondary)),
        ]),
        const Spacer(),
        _NextButton(
          label: 'Confirmer la commande',
          onTap: (canSubmit && !submitting) ? onSubmit : null,
          loading: submitting,
        ),
      ]),
    );
  }
}

// ─── Bouton dégradé cyan (style "Livraison effectuée") ───────────────────────
class _NextButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool loading;

  const _NextButton({required this.label, this.icon, this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final active = onTap != null && !loading;
    return GestureDetector(
      onTap: active ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [Color(0xFF00D4FF), Color(0xFF0099CC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: active ? null : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
          boxShadow: active
              ? [BoxShadow(color: const Color(0xFF00D4FF).withValues(alpha: 0.30), blurRadius: 28, offset: const Offset(0, 8))]
              : [],
        ),
        child: Center(
          child: loading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: active ? Colors.black : const Color(0xFF5A6A8A),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (icon != null) ...[
                      const SizedBox(width: 8),
                      Icon(icon, color: active ? Colors.black : const Color(0xFF5A6A8A), size: 16),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _RouteRow({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: color, size: 14),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ]);
  }
}
