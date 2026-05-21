import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/error/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/map_theme_provider.dart';
import '../client_profile/data/favorite_addresses_repository.dart';
import '../deliveries/data/orders_repository.dart';
import '../home_driver/navigation/map_theme.dart';
import '../home_driver/navigation/navigation_service.dart';

// ─── Heights par step ────────────────────────────────────────────────────────
const _kPanelHeights = [180.0, 290.0, 310.0, 260.0]; // step 0, 1, 2, 3

class OrderCreateScreen extends ConsumerStatefulWidget {
  final String orderType;
  const OrderCreateScreen({super.key, this.orderType = 'DELIVERY'});

  @override
  ConsumerState<OrderCreateScreen> createState() => _OrderCreateScreenState();
}

class _OrderCreateScreenState extends ConsumerState<OrderCreateScreen> {
  final _repo = OrdersRepository();

  // ── Constants ────────────────────────────────────────────────────────────
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
  double? _estimatedPrice; // prix course (= ce que le livreur gagne)
  double _demFee = 0.0;    // frais DEM prélevés en sus au client
  bool _freeCourseEligible = false; // 2ème course gratuite (100 premiers clients)
  bool _loadingSurge  = false;
  bool _priceTimedOut = false;
  bool _loadingGps    = false;
  bool _submitting    = false;
  Timer? _surgeDebounce;
  Timer? _priceTimeoutTimer;
  List<LatLng> _routePoints = [];
  Map<String, dynamic>? _currentUser;

  // ── Dio public (Google Places, OSRM) — sans token JWT ────────────────────
  late final _publicDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  // ── Adresses favorites ───────────────────────────────────────────────────
  final _favRepo = FavoriteAddressesRepository();
  List<Map<String, dynamic>> _favorites = [];

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _loadMapStyle();
    _fetchGpsInit();
    _loadUser();
    _checkFreeCourse();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    try {
      final list = await _favRepo.getAll();
      if (mounted) setState(() => _favorites = list);
    } catch (_) {}
  }

  void _applyFavorite(Map<String, dynamic> fav) {
    final lat = (fav['lat'] as num).toDouble();
    final lng = (fav['lng'] as num).toDouble();
    final addr = fav['address'] as String;
    setState(() {
      if (_isSelectingPickup) {
        _pickupCtrl.text = addr; _pickupLat = lat; _pickupLng = lng;
      } else {
        _deliveryCtrl.text = addr; _deliveryLat = lat; _deliveryLng = lng;
      }
      _suggestions = [];
    });
    _centerMap(LatLng(lat, lng));
    _updateEstimate();
  }

  Future<void> _loadUser() async {
    final user = await AuthStorage.getUser();
    if (mounted) setState(() => _currentUser = user);
  }

  Future<void> _checkFreeCourse() async {
    final eligible = await _repo.checkFreeCourse();
    if (mounted) setState(() => _freeCourseEligible = eligible);
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
    _priceTimeoutTimer?.cancel();
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
    final isNight = ref.read(mapNightProvider);
    final style = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
    if (mounted) setState(() => _mapStyle = style);
  }

  Future<void> _toggleMapTheme() async {
    await ref.read(mapNightProvider.notifier).toggle();
    await _loadMapStyle();
  }

  // ── GPS ──────────────────────────────────────────────────────────────────
  Future<void> _fetchGpsInit() async {
    setState(() => _loadingGps = true);
    try {
      final pos = await NavigationService.requestAndGetPosition();
      if (pos != null && mounted) {
        final ll = LatLng(pos.latitude, pos.longitude);
        _currentCameraPos = ll;
        _centerMap(ll);
        _pickupLat = ll.latitude;
        _pickupLng = ll.longitude;
        _reverseGeocode(ll, forPickup: true);
      }
    } catch (_) {
      // fallback Dakar
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  void _centerMap(LatLng pos) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: pos, zoom: 14, tilt: 30)),
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

  // ── Autocomplete Google Places ────────────────────────────────────────────
  void _onAddressChanged(String query, {required bool forPickup}) {
    setState(() => _isSelectingPickup = forPickup);
    _searchDebounce?.cancel();
    if (query.trim().length < 3) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 450), () async {
      setState(() => _isSearching = true);
      try {
        final res = await _publicDio.get(
          'https://maps.googleapis.com/maps/api/place/autocomplete/json',
          queryParameters: {
            'input': query,
            'location': '14.6937,-17.4441',
            'radius': '60000',
            'components': 'country:sn',
            'language': 'fr',
            'key': AppConfig.mapsApiKey,
          },
        );
        if (mounted && res.statusCode == 200) {
          final status = res.data['status'] as String?;
          final preds = status == 'OK'
              ? List<Map<String, dynamic>>.from(res.data['predictions'])
              : <Map<String, dynamic>>[];
          setState(() { _suggestions = preds; _isSearching = false; });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  Future<void> _selectSuggestion(Map<String, dynamic> place) async {
    final placeId = place['place_id'] as String?;
    if (placeId == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _suggestions = []);
    try {
      final res = await _publicDio.get(
        'https://maps.googleapis.com/maps/api/place/details/json',
        queryParameters: {
          'place_id': placeId,
          'fields': 'geometry,name,formatted_address',
          'language': 'fr',
          'key': AppConfig.mapsApiKey,
        },
      );
      if (res.statusCode == 200 && res.data['status'] == 'OK') {
        final loc = res.data['result']['geometry']['location'];
        final lat = (loc['lat'] as num).toDouble();
        final lng = (loc['lng'] as num).toDouble();
        final name = (place['structured_formatting']?['main_text'] as String?)
            ?? place['description'] as String? ?? '';
        setState(() {
          if (_isSelectingPickup) {
            _pickupLat = lat; _pickupLng = lng; _pickupCtrl.text = name;
          } else {
            _deliveryLat = lat; _deliveryLng = lng; _deliveryCtrl.text = name;
          }
        });
        _centerMap(LatLng(lat, lng));
        _updateEstimate();
      }
    } catch (_) {}
  }

  // ── Pricing ──────────────────────────────────────────────────────────────
  void _updateEstimate() {
    if (_pickupLat == null || _deliveryLat == null) return;
    _surgeDebounce?.cancel();
    _surgeDebounce = Timer(const Duration(milliseconds: 800), _computeEstimate);
  }

  void _retryEstimate() {
    setState(() => _priceTimedOut = false);
    _updateEstimate();
  }

  void _swapAddresses() {
    setState(() {
      final tmpText = _pickupCtrl.text;
      final tmpLat  = _pickupLat;
      final tmpLng  = _pickupLng;
      _pickupCtrl.text   = _deliveryCtrl.text;
      _pickupLat         = _deliveryLat;
      _pickupLng         = _deliveryLng;
      _deliveryCtrl.text = tmpText;
      _deliveryLat       = tmpLat;
      _deliveryLng       = tmpLng;
      _isSelectingPickup = true;
    });
    if (_pickupLat != null || _deliveryLat != null) _updateEstimate();
  }

  // ── Validation téléphone ─────────────────────────────────────────────────
  bool _validatePhone(TextEditingController ctrl, String label) {
    final digits = ctrl.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Numéro $label requis'),
        backgroundColor: AppColors.error,
      ));
      return false;
    }
    if (digits.length < 9) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Numéro $label invalide — 9 chiffres minimum'),
        backgroundColor: AppColors.error,
      ));
      return false;
    }
    return true;
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
      final res = await _publicDio.get(
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
      final res = await _publicDio.get(
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
    setState(() { _loadingSurge = true; _priceTimedOut = false; });

    _priceTimeoutTimer?.cancel();
    _priceTimeoutTimer = Timer(const Duration(seconds: 20), () {
      if (mounted && _loadingSurge) {
        setState(() { _loadingSurge = false; _priceTimedOut = true; });
      }
    });

    try {
      // Lance route (visuel) et estimation en parallèle — pas séquentiels
      final routeFuture    = _fetchRouteAndDistance(_pickupLat!, _pickupLng!, _deliveryLat!, _deliveryLng!);
      final estimateFuture = _repo.getEstimate(
        pickupLat: _pickupLat!, pickupLng: _pickupLng!,
        deliveryLat: _deliveryLat!, deliveryLng: _deliveryLng!,
        orderType: widget.orderType,
      );

      // Affiche le prix dès que l'estimation revient (sans attendre la route)
      final estimate = await estimateFuture;
      if (estimate != null && mounted) {
        setState(() {
          _surgeMultiplier = (estimate['surgeMultiplier'] as num?)?.toDouble() ?? 1.0;
          _estimatedPrice  = (estimate['price']           as num?)?.toDouble();
          _demFee          = (estimate['demFee']          as num?)?.toDouble() ?? 0.0;
          _loadingSurge    = false;
          _priceTimedOut   = false;
        });
      } else if (mounted) {
        setState(() { _loadingSurge = false; _priceTimedOut = true; });
      }

      // Route visuelle — peut arriver après le prix, c'est OK
      final routeData = await routeFuture;
      if (routeData != null && mounted) {
        setState(() => _routePoints = routeData['points'] as List<LatLng>);
      } else if (mounted && _pickupLat != null && _deliveryLat != null) {
        setState(() => _routePoints = [LatLng(_pickupLat!, _pickupLng!), LatLng(_deliveryLat!, _deliveryLng!)]);
      }
    } catch (_) {
      if (mounted) setState(() { _loadingSurge = false; _priceTimedOut = true; });
    } finally {
      _priceTimeoutTimer?.cancel();
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


  // ── Step navigation ───────────────────────────────────────────────────────
  bool get _routeComplete => _pickupLat != null && _deliveryLat != null;

  void _goStep(int step) {
    setState(() => _step = step);
    _pageCtrl.animateToPage(step,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    if (step >= 1 && _pickupLat != null && _deliveryLat != null) {
      _fitBothPoints();
    }
  }

  void _fitBothPoints() {
    final sw = LatLng(
      min(_pickupLat!, _deliveryLat!),
      min(_pickupLng!, _deliveryLng!),
    );
    final ne = LatLng(
      max(_pickupLat!, _deliveryLat!),
      max(_pickupLng!, _deliveryLng!),
    );
    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(LatLngBounds(southwest: sw, northeast: ne), 90),
    );
  }

  // ── Contacts ─────────────────────────────────────────────────────────────
  Future<void> _pickContact({
    required TextEditingController nameCtrl,
    required TextEditingController phoneCtrl,
  }) async {
    final status = await FlutterContacts.permissions.request(PermissionType.read);
    final granted = status == PermissionStatus.granted || status == PermissionStatus.limited;

    if (!granted) {
      if (!mounted) return;
      final canOpenSettings = status == PermissionStatus.permanentlyDenied ||
          status == PermissionStatus.restricted;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Accès aux contacts refusé'),
        action: canOpenSettings
            ? SnackBarAction(
                label: 'Paramètres',
                onPressed: FlutterContacts.permissions.openSettings,
              )
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
        if (_demFee > 0) 'demFee': _demFee,
        if (_freeCourseEligible) 'freeCourse': true,
      });

      if (_estimatedPrice != null) order['price'] = _estimatedPrice;
      if (_demFee > 0) order['demFee'] = _demFee;
      if (_freeCourseEligible) order['freeCourse'] = true;
      
      if (mounted) context.pushReplacement('/orders/confirmation', extra: order);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.error),
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
    final keyboardH     = MediaQuery.of(context).viewInsets.bottom;
    final bottomSafeArea = MediaQuery.of(context).viewPadding.bottom;
    // +24px supplémentaires pour les appareils avec indicateur maison (iPhone X+)
    final extraH    = bottomSafeArea > 20 ? 24.0 : 0.0;
    final panelH    = _isMapPlacementMode ? 90.0 : _kPanelHeights[_step] + extraH;

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
      final pickupLabel = _pickupCtrl.text.isNotEmpty ? _pickupCtrl.text : 'Point de départ';
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(_pickupLat!, _pickupLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: 'Départ',
          snippet: pickupLabel.length > 60 ? '${pickupLabel.substring(0, 57)}…' : pickupLabel,
        ),
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() {
            _isSelectingPickup = true;
            _isMapPlacementMode = true;
          });
          _centerMap(LatLng(_pickupLat!, _pickupLng!));
        },
      ));
    }
    if (_deliveryLat != null && (_isSelectingPickup || !_isMapPlacementMode)) {
      final deliveryLabel = _deliveryCtrl.text.isNotEmpty ? _deliveryCtrl.text : 'Destination';
      markers.add(Marker(
        markerId: const MarkerId('delivery'),
        position: LatLng(_deliveryLat!, _deliveryLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: 'Destination',
          snippet: deliveryLabel.length > 60 ? '${deliveryLabel.substring(0, 57)}…' : deliveryLabel,
        ),
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() {
            _isSelectingPickup = false;
            _isMapPlacementMode = true;
          });
          _centerMap(LatLng(_deliveryLat!, _deliveryLng!));
        },
      ));
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(children: [

        // ── MAP ────────────────────────────────────────────────────────────
        SizedBox.expand(
          child: GoogleMap(
            initialCameraPosition: const CameraPosition(target: _dakar, zoom: 14, tilt: 30),
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

        // ── MAP THEME TOGGLE ──────────────────────────────────────────────────
        Positioned(
          right: 16,
          bottom: panelH + 116 + keyboardH,
          child: GestureDetector(
            onTap: _toggleMapTheme,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AppColors.surface, shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8)],
              ),
              child: Icon(
                ref.watch(mapNightProvider) ? Icons.wb_sunny_outlined : Icons.nightlight_round,
                color: ref.watch(mapNightProvider) ? const Color(0xFFFFB300) : AppColors.primary,
                size: 20,
              ),
            ),
          ),
        ),

        // ── RECENTER BTN ───────────────────────────────────────────────────
        Positioned(
          right: 16,
          bottom: panelH + 60 + keyboardH,
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
                    onDotLongPress: () {
                      FocusScope.of(context).unfocus();
                      setState(() { _isSelectingPickup = true; _isMapPlacementMode = true; });
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    child: Row(children: [
                      Container(width: 2, height: 16, color: AppColors.textSecondary.withValues(alpha: 0.3)),
                      const Spacer(),
                      // ── Swap départ ↔ arrivée ──────────────────────────
                      GestureDetector(
                        onTap: _swapAddresses,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.30)),
                          ),
                          child: const Icon(Icons.swap_vert, color: AppColors.primary, size: 16),
                        ),
                      ),
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
                    onDotLongPress: () {
                      FocusScope.of(context).unfocus();
                      setState(() { _isSelectingPickup = false; _isMapPlacementMode = true; });
                    },
                  ),

                  // ── Chips adresses favorites ──────────────────────────
                  if (_favorites.isNotEmpty && !_isMapPlacementMode) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 32,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _favorites.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (_, i) {
                          final fav = _favorites[i];
                          return GestureDetector(
                            onTap: () => _applyFavorite(fav),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF0CB8DE), Color(0xFF0671BA)],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF0CB8DE).withValues(alpha: 0.35),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(fav['icon'] as String? ?? '📍', style: const TextStyle(fontSize: 13)),
                                const SizedBox(width: 5),
                                Text(fav['label'] as String? ?? '',
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
                  ],

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
            margin: EdgeInsets.only(bottom: keyboardH),
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
                              onPickMe: () {
                                _fillMe(_senderNameCtrl, _senderPhoneCtrl);
                                if (_senderPhoneCtrl.text.length >= 9) _goStep(2);
                              },
                              onPhoneComplete: () => _goStep(2),
                              onNext: () {
                                if (!_validatePhone(_senderPhoneCtrl, 'expéditeur')) return;
                                _goStep(2);
                              },
                            ),
                            _Step2Panel(
                              orderType: widget.orderType,
                              nameCtrl: _receiverNameCtrl,
                              phoneCtrl: _receiverPhoneCtrl,
                              descriptionCtrl: _descriptionCtrl,
                              onPickContact: () => _pickContact(nameCtrl: _receiverNameCtrl, phoneCtrl: _receiverPhoneCtrl),
                              onPickMe: () {
                                _fillMe(_receiverNameCtrl, _receiverPhoneCtrl);
                                if (_receiverPhoneCtrl.text.length >= 9) {
                                  _updateEstimate();
                                  _goStep(3);
                                }
                              },
                              onPhoneComplete: () {
                                _updateEstimate();
                                _goStep(3);
                              },
                              onNext: () {
                                if (!_validatePhone(_receiverPhoneCtrl, 'destinataire')) return;
                                _updateEstimate();
                                _goStep(3);
                              },
                            ),
                            _Step3Panel(
                              pickupLabel: _pickupCtrl.text.isNotEmpty ? _pickupCtrl.text : 'Départ',
                              deliveryLabel: _deliveryCtrl.text.isNotEmpty ? _deliveryCtrl.text : 'Destination',
                              estimatedPrice: _estimatedPrice,
                              demFee: _demFee,
                              freeCourse: _freeCourseEligible,
                              surgeMultiplier: _surgeMultiplier,
                              loadingSurge: _loadingSurge,
                              timedOut: _priceTimedOut,
                              submitting: _submitting,
                              canSubmit: _routeComplete && _estimatedPrice != null,
                              onRetry: _retryEstimate,
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
  final VoidCallback? onDotLongPress;

  const _AddressField({
    required this.controller, required this.hint, required this.dotColor,
    required this.active, required this.onTap, required this.onChanged, required this.onMapTap,
    this.onDotLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: dotColor.withValues(alpha: active ? 0.14 : 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: dotColor.withValues(alpha: active ? 0.85 : 0.45),
            width: active ? 1.4 : 1.0,
          ),
          boxShadow: active
              ? [BoxShadow(color: dotColor.withValues(alpha: 0.22), blurRadius: 20, spreadRadius: 0)]
              : [BoxShadow(color: dotColor.withValues(alpha: 0.08), blurRadius: 6)],
        ),
        child: Row(children: [
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onDotLongPress,
            onLongPress: onDotLongPress,
            child: active
                ? _PulsingDot(color: dotColor)
                : Container(width: 10, height: 10, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              onTap: onTap,
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
            icon: Icon(Icons.location_on, color: active ? dotColor : Colors.white.withValues(alpha: 0.80), size: 20),
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

  IconData _iconForTypes(List<dynamic> types) {
    if (types.any((t) => t.toString().contains('transit') || t.toString().contains('bus') || t.toString().contains('station'))) {
      return Icons.directions_bus_outlined;
    }
    if (types.any((t) => t.toString().contains('hospital') || t.toString().contains('health'))) {
      return Icons.local_hospital_outlined;
    }
    if (types.any((t) => t.toString().contains('airport'))) return Icons.flight_outlined;
    if (types.any((t) => t.toString().contains('school') || t.toString().contains('university'))) {
      return Icons.school_outlined;
    }
    if (types.any((t) => t.toString().contains('park') || t.toString().contains('natural'))) {
      return Icons.park_outlined;
    }
    if (types.any((t) => t.toString().contains('restaurant') || t.toString().contains('food'))) {
      return Icons.restaurant_outlined;
    }
    return Icons.place_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final keyboardH  = MediaQuery.of(context).viewInsets.bottom;
    final safeTop    = MediaQuery.of(context).padding.top;
    final screenH    = MediaQuery.of(context).size.height;
    final maxH       = (screenH - keyboardH - safeTop - 160).clamp(100.0, 320.0);
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2540),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 20)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: loading
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
            : ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: suggestions.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: Colors.white.withValues(alpha: 0.07)),
                itemBuilder: (_, i) {
                  final p = suggestions[i];
                  final fmt = p['structured_formatting'] as Map<String, dynamic>?;
                  final main = fmt?['main_text'] as String?
                      ?? p['description'] as String? ?? '';
                  final secondary = fmt?['secondary_text'] as String? ?? '';
                  final types = p['types'] as List<dynamic>? ?? [];
                  final icon = _iconForTypes(types);
                  return InkWell(
                    onTap: () => onSelect(p),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon,
                                color: Colors.white.withValues(alpha: 0.75), size: 16),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(main,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                if (secondary.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(secondary,
                                      style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.50),
                                          fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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
          const Text('Astuce',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          RichText(
            maxLines: 3,
            text: TextSpan(
              style: TextStyle(color: Colors.white.withValues(alpha: 0.70), fontSize: 14, fontWeight: FontWeight.normal, height: 1.4),
              children: [
                const TextSpan(text: 'Utiliser les champs de recherche ou le bouton '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(Icons.location_on, color: Colors.white.withValues(alpha: 0.70), size: 13),
                ),
                const TextSpan(text: ' pour placer un point sur la carte.'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (!routeComplete) ...[
            const Text(
              'Définissez les deux adresses pour continuer',
              style: TextStyle(color: Colors.white70, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
          ],
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
  final VoidCallback? onPhoneComplete;
  final VoidCallback onNext;

  const _Step1Panel({
    required this.orderType,
    required this.nameCtrl, required this.phoneCtrl,
    required this.onPickContact, this.onPickMe,
    this.onPhoneComplete,
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
            onPhoneComplete: onPhoneComplete,
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
  final VoidCallback? onPhoneComplete;
  final VoidCallback onNext;

  const _Step2Panel({
    required this.orderType,
    required this.nameCtrl, required this.phoneCtrl,
    required this.descriptionCtrl,
    required this.onPickContact, this.onPickMe,
    this.onPhoneComplete,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _ContactMini(
                    label: orderType == 'RIDE' ? 'Destination' : 'Destinataire',
                    dotColor: AppColors.error,
                    nameCtrl: nameCtrl,
                    phoneCtrl: phoneCtrl,
                    onPick: onPickContact,
                    onPickMe: onPickMe,
                    onPhoneComplete: onPhoneComplete,
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
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
  final VoidCallback? onPhoneComplete;
  const _ContactMini({required this.label, required this.dotColor, required this.nameCtrl, required this.phoneCtrl, required this.onPick, this.onPickMe, this.onPhoneComplete});

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
        const SizedBox(height: 10),
        TextField(
          controller: nameCtrl,
          inputFormatters: [NameInputFormatter()],
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Nom complet',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 14),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Icon(Icons.person_outline_rounded,
                  color: Colors.white.withValues(alpha: 0.55), size: 18),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            fillColor: Colors.white.withValues(alpha: 0.08), filled: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: phoneCtrl,
          keyboardType: TextInputType.phone,
          inputFormatters: [DigitsOnlyFormatter()],
          style: const TextStyle(color: Colors.white, fontSize: 14),
          onChanged: (v) { if (v.length >= 9) onPhoneComplete?.call(); },
          decoration: InputDecoration(
            hintText: 'Numéro de téléphone',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 14),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Icon(Icons.phone_outlined,
                  color: visibleDot.withValues(alpha: 0.80), size: 18),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            prefixText: '+221 ',
            prefixStyle: TextStyle(
                color: visibleDot, fontWeight: FontWeight.w700, fontSize: 14),
            fillColor: Colors.white.withValues(alpha: 0.08), filled: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
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
  final double demFee;
  final bool freeCourse;
  final double surgeMultiplier;
  final bool loadingSurge;
  final bool timedOut;
  final bool submitting;
  final bool canSubmit;
  final VoidCallback onRetry;
  final VoidCallback onSubmit;

  const _Step3Panel({
    required this.pickupLabel, required this.deliveryLabel,
    required this.estimatedPrice, required this.demFee,
    required this.freeCourse,
    required this.surgeMultiplier,
    required this.loadingSurge,
    required this.timedOut,
    required this.submitting,
    required this.canSubmit,
    required this.onRetry,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(children: [
        // Contenu scrollable (s'adapte si bannière promo présente)
        Expanded(
          child: SingleChildScrollView(
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

        // Bannière 2ème course gratuite
        if (freeCourse) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF00C853).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.40)),
            ),
            child: const Row(children: [
              Text('🎁', style: TextStyle(fontSize: 16)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '2ème course offerte — vous faites partie des 100 premiers !',
                  style: TextStyle(color: Color(0xFF00C853), fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
        ],

        // Price card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: loadingSurge
              ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
              : timedOut && estimatedPrice == null
                  // ── État timeout : impossible de calculer le prix ──
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off_outlined, color: AppColors.textSecondary, size: 22),
                        const SizedBox(height: 6),
                        const Text(
                          'Impossible de calculer le prix',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: onRetry,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.40)),
                            ),
                            child: const Text('Réessayer',
                                style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    )
                  // ── État normal : affichage du prix ──
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Ligne : prix course + surge badge
                        Row(
                          children: [
                            const Text('Course', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            const Spacer(),
                            if (surgeMultiplier > 1.0) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF9800).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.30)),
                                ),
                                child: Row(children: [
                                  const Icon(Icons.flash_on, color: Color(0xFFFF9800), size: 11),
                                  const SizedBox(width: 2),
                                  Text('×${surgeMultiplier.toStringAsFixed(1)}',
                                      style: const TextStyle(color: Color(0xFFFF9800), fontSize: 10, fontWeight: FontWeight.bold)),
                                ]),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              estimatedPrice != null ? '${estimatedPrice!.toInt()} FCFA' : '—',
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        // Ligne : frais DEM (visible uniquement si > 0)
                        if (estimatedPrice != null && demFee > 0) ...[
                          const SizedBox(height: 4),
                          Row(children: [
                            const Text('Frais DEM', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            const Spacer(),
                            Text('+${demFee.toInt()} FCFA',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          ]),
                          Divider(color: Colors.white.withValues(alpha: 0.10), height: 14),
                        ],
                        // Ligne : total client
                        if (estimatedPrice != null) ...[
                          Row(children: [
                            const Text('TOTAL', style: TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                            const Spacer(),
                            if (freeCourse)
                              const Row(children: [
                                Text('0 FCFA', style: TextStyle(color: Color(0xFF00C853), fontSize: 22, fontWeight: FontWeight.bold)),
                                SizedBox(width: 6),
                                Text('🎁', style: TextStyle(fontSize: 16)),
                              ])
                            else
                              Text(
                                '${(estimatedPrice! + demFee).toInt()} FCFA',
                                style: const TextStyle(color: AppColors.primary, fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                          ]),
                        ] else
                          const Text('—', style: TextStyle(color: AppColors.textSecondary, fontSize: 22)),
                      ],
                    ),
        ),
        const SizedBox(height: 8),
            ]),
          ),
        ),
        // Bouton toujours visible en bas
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
