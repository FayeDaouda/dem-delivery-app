import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../deliveries/data/orders_repository.dart';
import '../home_driver/navigation/map_theme.dart';

class OrderCreateScreen extends StatefulWidget {
  /// 'RIDE' = transport humain (Thiak Thiak) | 'DELIVERY' = livraison colis
  final String orderType;
  const OrderCreateScreen({super.key, this.orderType = 'DELIVERY'});

  @override
  State<OrderCreateScreen> createState() => _OrderCreateScreenState();
}

class _OrderCreateScreenState extends State<OrderCreateScreen> {
  final _repo = OrdersRepository();

  // ── Constantes ────────────────────────────────────────────────────────────
  static const double _baseFare = 500;
  static const double _pricePerKm = 200;
  static const LatLng _dakar = LatLng(14.6937, -17.4441);

  // ── Map State ──────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  String? _mapStyle;
  bool _isMapMoving = false;
  LatLng _currentCameraPos = _dakar;

  // ── Mode de sélection ──────────────────────────────────────────────────────
  bool _isSelectingPickup = true;
  bool _isMapPlacementMode = false;

  // ── Form & Coordinates ─────────────────────────────────────────────────────
  final _pickupAddressCtrl = TextEditingController();
  final _deliveryAddressCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  double? _pickupLat;
  double? _pickupLng;
  double? _deliveryLat;
  double? _deliveryLng;

  // ── Pricing State ──────────────────────────────────────────────────────────
  double _surgeMultiplier = 1.0;
  double? _estimatedPrice;
  bool _loadingSurge = false;
  bool _loadingGps = false;
  bool _submitting = false;
  Timer? _surgeDebounce;

  // ── Autocomplete ───────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _searchSuggestions = [];
  bool _isSearchingAddress = false;
  Timer? _addressSearchDebounce;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _fetchGpsInit();
  }

  @override
  void dispose() {
    _surgeDebounce?.cancel();
    _addressSearchDebounce?.cancel();
    _pickupAddressCtrl.dispose();
    _deliveryAddressCtrl.dispose();
    _descriptionCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadMapStyle() async {
    final style = await rootBundle.loadString(MapTheme.styleAsset);
    if (mounted) setState(() => _mapStyle = style);
  }

  // ── Initial GPS Fetch (Centrage) ───────────────────────────────────────────
  Future<void> _fetchGpsInit() async {
    setState(() => _loadingGps = true);
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition();
      final latLng = LatLng(pos.latitude, pos.longitude);
      _currentCameraPos = latLng;
      
      _centerMap(latLng);
      // Au démarrage, on est en mode "Pickup"
      _pickupLat = latLng.latitude;
      _pickupLng = latLng.longitude;
      _reverseGeocode(latLng);
    } catch (_) {
      // Fallback Waze/Dakar
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  // ── Map Events ─────────────────────────────────────────────────────────────
  void _centerMap(LatLng position) {
    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: position, zoom: 16),
        ),
      );
    }
  }

  Future<void> _onCameraIdle() async {
    setState(() => _isMapMoving = false);
  }

  // ── Confirmer la position depuis la map ────────────────────────────────────
  Future<void> _confirmMapPlacement() async {
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
    await _reverseGeocode(_currentCameraPos);
  }

  // ── Geocoding ──────────────────────────────────────────────────────────────
  Future<void> _reverseGeocode(LatLng pos) async {
    try {
      List<geo.Placemark> placemarks = await geo.placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      ).timeout(const Duration(seconds: 5));

      if (placemarks.isNotEmpty) {
        final p = placemarks[0];
        final name = p.street ?? p.name ?? '';
        final local = p.subLocality ?? p.locality ?? '';
        final addr = name.isNotEmpty ? '$name, $local' : local;
        
        if (mounted) {
          setState(() {
            if (_isSelectingPickup) {
              _pickupAddressCtrl.text = addr.isNotEmpty ? addr : 'Départ sélect.';
            } else {
              _deliveryAddressCtrl.text = addr.isNotEmpty ? addr : 'Dest. sélect.';
            }
          });
        }
      }
    } catch (_) {
      // Ignorer l'erreur, le placeholder par défaut reste
      if (mounted) {
        setState(() {
          if (_isSelectingPickup && _pickupAddressCtrl.text.isEmpty) {
             _pickupAddressCtrl.text = 'Position (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})';
          } else if (!_isSelectingPickup && _deliveryAddressCtrl.text.isEmpty) {
             _deliveryAddressCtrl.text = 'Position (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})';
          }
        });
      }
    }
  }

  // Permet à l'utilisateur de taper et chercher (Geocoding texte manuel)
  Future<void> _geocodeAddress(String address) async {
    if (address.trim().isEmpty) return;
    try {
      List<geo.Location> locations = await geo.locationFromAddress(address).timeout(const Duration(seconds: 5));
      if (locations.isNotEmpty) {
        final loc = locations[0];
        final latLng = LatLng(loc.latitude, loc.longitude);
        _centerMap(latLng); // Ça va déclencher _onCameraIdle
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lieu introuvable, essayez de déplacer la carte.')),
        );
      }
    }
  }

  // ── Autocomplete / Suggestions ─────────────────────────────────────────────
  void _onAddressChanged(String query) {
    _addressSearchDebounce?.cancel();
    if (query.trim().length < 3) {
      if (_searchSuggestions.isNotEmpty) setState(() => _searchSuggestions = []);
      return;
    }
    
    _addressSearchDebounce = Timer(const Duration(milliseconds: 600), () async {
      setState(() => _isSearchingAddress = true);
      try {
        final dio = Dio(BaseOptions(headers: {'User-Agent': 'com.dem.app/1.0'}));
        final response = await dio.get(
          'https://nominatim.openstreetmap.org/search',
          queryParameters: {
            'q': query,
            'format': 'json',
            'limit': 5,
            'countrycodes': 'sn',
          },
        );
        if (mounted) {
          setState(() {
            _searchSuggestions = List<Map<String, dynamic>>.from(response.data);
            _isSearchingAddress = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isSearchingAddress = false);
      }
    });
  }

  Future<void> _selectSuggestion(Map<String, dynamic> place) async {
    final lat = double.tryParse(place['lat']?.toString() ?? '');
    final lng = double.tryParse(place['lon']?.toString() ?? '');
    if (lat == null || lng == null) return;
    
    final name = place['name'] ?? place['display_name'] ?? '';
    
    setState(() {
      _searchSuggestions = [];
      if (_isSelectingPickup) {
        _pickupLat = lat;
        _pickupLng = lng;
        _pickupAddressCtrl.text = name;
      } else {
        _deliveryLat = lat;
        _deliveryLng = lng;
        _deliveryAddressCtrl.text = name;
      }
    });
    
    FocusScope.of(context).unfocus();
    _centerMap(LatLng(lat, lng));
    _updateEstimate();
  }

  // ── Pricing ────────────────────────────────────────────────────────────────
  void _updateEstimate() {
    if (_pickupLat == null || _deliveryLat == null) return;

    _surgeDebounce?.cancel();
    _surgeDebounce = Timer(const Duration(milliseconds: 800), _computeEstimate);
  }

  Future<void> _computeEstimate() async {
    if (_pickupLat == null || _deliveryLat == null) return;
    setState(() => _loadingSurge = true);

    try {
      final surge = await _repo.getSurgeMultiplier(_pickupLat!, _pickupLng!);
      final dist = _haversineKm(_pickupLat!, _pickupLng!, _deliveryLat!, _deliveryLng!);
      final price = (_baseFare + dist * _pricePerKm) * surge;

      if (mounted) {
        setState(() {
          _surgeMultiplier = surge;
          _estimatedPrice = price.roundToDouble();
          _loadingSurge = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSurge = false);
    }
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
        sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  // ── Soumission ────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (_pickupLat == null || _pickupLng == null) {
      _showError('Sélectionnez un point de départ sur la carte.');
      return;
    }
    if (_deliveryLat == null || _deliveryLng == null) {
      _showError('Sélectionnez un point d\'arrivée sur la carte.');
      return;
    }
    if (_pickupAddressCtrl.text.trim().isEmpty) {
      _pickupAddressCtrl.text = 'Position (${_pickupLat!.toStringAsFixed(4)}, ${_pickupLng!.toStringAsFixed(4)})';
    }
    if (_deliveryAddressCtrl.text.trim().isEmpty) {
      _deliveryAddressCtrl.text = 'Position (${_deliveryLat!.toStringAsFixed(4)}, ${_deliveryLng!.toStringAsFixed(4)})';
    }

    setState(() => _submitting = true);
    try {
      final order = await _repo.createOrder({
        'orderType': widget.orderType,
        'pickupAddress': _pickupAddressCtrl.text.trim(),
        'pickupLatitude': _pickupLat,
        'pickupLongitude': _pickupLng,
        'deliveryAddress': _deliveryAddressCtrl.text.trim(),
        'deliveryLatitude': _deliveryLat,
        'deliveryLongitude': _deliveryLng,
        if (widget.orderType == 'DELIVERY')
          'description': _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
      });

      if (mounted) context.pushReplacement('/orders/confirmation', extra: order);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Si la destination existe et qu'on cherche le point de départ, afficher une ligne
    Set<Polyline> polylines = {};
    if (_pickupLat != null && _deliveryLat != null) {
      polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        points: [
          LatLng(_pickupLat!, _pickupLng!),
          LatLng(_deliveryLat!, _deliveryLng!),
        ],
        color: AppColors.primary,
        width: 4,
      ));
    }

    // Afficher les marqueurs inactifs
    Set<Marker> markers = {};
    if (_isSelectingPickup && _deliveryLat != null) {
      markers.add(Marker(
        markerId: const MarkerId('delivery'),
        position: LatLng(_deliveryLat!, _deliveryLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ));
    } else if (!_isSelectingPickup && _pickupLat != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(_pickupLat!, _pickupLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ));
    }

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // ── Map ──
          SizedBox.expand(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: _dakar,
                zoom: 15,
              ),
              onMapCreated: (ctrl) => _mapController = ctrl,
              style: _mapStyle,
              onCameraMoveStarted: () => setState(() => _isMapMoving = true),
              onCameraMove: (pos) => _currentCameraPos = pos.target,
              onCameraIdle: _onCameraIdle,
              polylines: polylines,
              markers: markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),

          // ── Center Pin ──
          if (_isMapPlacementMode)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 35.0),
                child: AnimatedScale(
                  scale: _isMapMoving ? 1.2 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.location_on,
                    size: 44,
                    color: _isSelectingPickup ? const Color(0xFF4CAF50) : AppColors.error,
                    shadows: [
                      Shadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4)),
                    ],
                  ),
                ),
              ),
            ),

          // ── Bouton recentrer ──
          if (_isMapPlacementMode)
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).size.height * 0.4 + 16,
            child: GestureDetector(
              onTap: _fetchGpsInit,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8),
                  ],
                ),
                child: _loadingGps
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location, color: AppColors.primary),
              ),
            ),
          ),

          // ── Top Bar (Inputs) ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 16),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Bouton retour
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () => Navigator.pop(context),
                            ),
                            Expanded(
                              child: Text(
                                widget.orderType == 'RIDE' ? 'Transport' : 'Livraison',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          ],
                        ),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(
                            children: [
                              // ── Pickup Field ──
                              GestureDetector(
                                onTap: () {
                                  setState(() { 
                                    _isSelectingPickup = true;
                                    _isMapPlacementMode = false;
                                  });
                                  if (_pickupLat != null) {
                                    _centerMap(LatLng(_pickupLat!, _pickupLng!));
                                  }
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: (_isSelectingPickup && !_isMapPlacementMode)
                                        ? Border.all(color: const Color(0xFF4CAF50), width: 2)
                                        : Border.all(color: Colors.transparent),
                                    borderRadius: BorderRadius.circular(8),
                                    color: (_isSelectingPickup && !_isMapPlacementMode) ? const Color(0xFF4CAF50).withValues(alpha: 0.05) : null,
                                  ),
                                  child: TextField(
                                    controller: _pickupAddressCtrl,
                                    onChanged: (val) {
                                      setState(() => _isSelectingPickup = true);
                                      _onAddressChanged(val);
                                    },
                                    onSubmitted: _geocodeAddress,
                                    textInputAction: TextInputAction.search,
                                    decoration: InputDecoration(
                                      hintText: 'Rechercher le départ...',
                                      prefixIcon: const Icon(Icons.circle, color: Color(0xFF4CAF50), size: 16),
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.map_outlined, color: Color(0xFF4CAF50)),
                                        tooltip: 'Placer sur la map',
                                        onPressed: () {
                                          setState(() {
                                            _isSelectingPickup = true;
                                            _isMapPlacementMode = true;
                                          });
                                        },
                                      ),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                  ),
                                ),
                              ),
                              
                              const Padding(
                                padding: EdgeInsets.only(left: 20),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Icon(Icons.more_vert, size: 20, color: AppColors.textSecondary),
                                ),
                              ),

                              // ── Delivery Field ──
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _isSelectingPickup = false;
                                    _isMapPlacementMode = false;
                                  });
                                  if (_deliveryLat != null) {
                                    _centerMap(LatLng(_deliveryLat!, _deliveryLng!));
                                  }
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: (!_isSelectingPickup && !_isMapPlacementMode)
                                        ? Border.all(color: AppColors.error, width: 2)
                                        : Border.all(color: Colors.transparent),
                                    borderRadius: BorderRadius.circular(8),
                                    color: (!_isSelectingPickup && !_isMapPlacementMode) ? AppColors.error.withValues(alpha: 0.05) : null,
                                  ),
                                  child: TextField(
                                    controller: _deliveryAddressCtrl,
                                    onChanged: (val) {
                                      setState(() => _isSelectingPickup = false);
                                      _onAddressChanged(val);
                                    },
                                    onSubmitted: _geocodeAddress,
                                    textInputAction: TextInputAction.search,
                                    decoration: InputDecoration(
                                      hintText: 'Rechercher la destination...',
                                      prefixIcon: const Icon(Icons.location_on, color: AppColors.error),
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.map_outlined, color: AppColors.error),
                                        tooltip: 'Placer sur la map',
                                        onPressed: () {
                                          setState(() {
                                            _isSelectingPickup = false;
                                            _isMapPlacementMode = true;
                                          });
                                        },
                                      ),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),

                  // ── Autocomplete Dropdown ──
                  if (_isSearchingAddress || _searchSuggestions.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 250),
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 16)
                        ]
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: _isSearchingAddress 
                          ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: AppColors.primary)))
                          : ListView.separated(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: _searchSuggestions.length,
                              separatorBuilder: (ctx, i) => Divider(height: 1, color: AppColors.textSecondary.withValues(alpha: 0.2)),
                              itemBuilder: (context, index) {
                                final place = _searchSuggestions[index];
                                final name = place['name']?.toString() ?? '';
                                final address = place['display_name']?.toString().replaceAll('$name, ', '') ?? '';
                                
                                return ListTile(
                                  leading: const Icon(Icons.place_outlined, color: AppColors.textSecondary),
                                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: address.isNotEmpty ? Text(address, style: const TextStyle(color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                                  onTap: () => _selectSuggestion(place),
                                );
                              },
                            ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Bottom Panel (Details & Submit) ──
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, -4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Ligne pour passer au suivant si pas fini
                  if (_isMapPlacementMode) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _confirmMapPlacement,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: _isSelectingPickup ? const Color(0xFF4CAF50) : AppColors.error,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Valider cette position', style: TextStyle(fontSize: 16, color: Colors.white)),
                      ),
                    ),
                  ] else ...[
                    if ((_isSelectingPickup && _pickupLat != null && _deliveryLat == null)) ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => setState(() {
                            _isSelectingPickup = false;
                            if (_deliveryLat != null) _centerMap(LatLng(_deliveryLat!, _deliveryLng!));
                          }),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Passer à la destination', style: TextStyle(color: AppColors.primary)),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (widget.orderType == 'DELIVERY') ...[
                      TextField(
                        controller: _descriptionCtrl,
                        decoration: InputDecoration(
                          hintText: 'Détails du colis (optionnel)...',
                          fillColor: AppColors.card,
                          filled: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Estimation ──
                    if (_estimatedPrice != null)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Prix estimé', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                          _loadingSurge
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Row(
                                  children: [
                                    if (_surgeMultiplier > 1.0)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 8.0),
                                        child: Icon(Icons.flash_on, color: Color(0xFFFF9800), size: 16),
                                      ),
                                    Text(
                                      '${_estimatedPrice!.toInt()} FCFA',
                                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                        ],
                      )
                    else
                      const Text('Sélectionnez les lieux pour voir le prix', style: TextStyle(color: AppColors.textSecondary)),

                    const SizedBox(height: 20),

                    // ── Commander ──
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (_pickupLat == null || _deliveryLat == null || _submitting) ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _submitting
                            ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text(widget.orderType == 'RIDE' ? 'Confirmer la course' : 'Valider la livraison', style: const TextStyle(fontSize: 16, color: Colors.white)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
