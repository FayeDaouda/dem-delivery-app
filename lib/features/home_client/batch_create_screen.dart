import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/error/app_exception.dart';
import '../../core/services/places_autocomplete_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../../core/theme/map_theme_provider.dart';
import '../../core/utils/dem_toast.dart';
import '../../core/utils/price_format.dart';
import '../../shared/widgets/colored_address_field.dart';
import '../../shared/widgets/map_theme_toggle_button.dart';
import '../../shared/widgets/place_suggestions_list.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/primary_button.dart';
import '../deliveries/data/orders_repository.dart';
import '../home_driver/navigation/map_theme.dart';

const _kBatchAccent = Color(0xFF0C7A5C);
const _placeSuggestionsColors = PlaceSuggestionsColors(
  background: Color(0xFF1A2540),
  border: Colors.white24,
  divider: _kBatchAccent,
  iconBg: _kBatchAccent,
  icon: Colors.white,
  mainText: Colors.white,
  secondaryText: _kBatchAccent,
  accent: _kBatchAccent,
);

const _dakar = LatLng(14.6937, -17.4441);
const int _kMinStops = 2;
const int _kMaxStops = 3;

class _StopEntry {
  final addressCtrl = TextEditingController();
  final receiverNameCtrl = TextEditingController();
  final receiverPhoneCtrl = TextEditingController();
  final focusNode = FocusNode();
  double? lat;
  double? lng;

  void dispose() {
    addressCtrl.dispose();
    receiverNameCtrl.dispose();
    receiverPhoneCtrl.dispose();
    focusNode.dispose();
  }
}

// ── Livraison groupée — même identité visuelle que "Livraison simple"
// (carte en fond, champs flottants colorés, sheet en dégradé) plutôt qu'une
// page dédiée déconnectée du reste du flux de commande. Voir
// colored_address_field.dart, partagé avec order_create_screen.dart.
class BatchCreateScreen extends ConsumerStatefulWidget {
  const BatchCreateScreen({super.key});

  @override
  ConsumerState<BatchCreateScreen> createState() => _BatchCreateScreenState();
}

class _BatchCreateScreenState extends ConsumerState<BatchCreateScreen> {
  final _repo = OrdersRepository();
  GoogleMapController? _mapController;
  String? _mapStyle;

  late final _publicDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );
  late final _placesService = PlacesAutocompleteService(_publicDio);
  String _sessionToken = PlacesAutocompleteService.newSessionToken();

  final _pickupCtrl = TextEditingController();
  final _pickupFocus = FocusNode();
  double? _pickupLat;
  double? _pickupLng;

  final List<_StopEntry> _stops = [_StopEntry(), _StopEntry()];

  // Champ actuellement en recherche (pour savoir où afficher les
  // suggestions) : 'pickup' ou l'index d'un arrêt.
  Object? _activeField;
  List<Map<String, dynamic>> _suggestions = [];
  bool _searching = false;
  Timer? _debounce;

  Map<String, dynamic>? _estimate;
  bool _estimating = false;
  String? _estimateError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _pickupFocus.addListener(() {
      if (_pickupFocus.hasFocus) setState(() => _activeField = 'pickup');
    });
    for (var i = 0; i < _stops.length; i++) {
      _attachFocusListener(i);
    }
  }

  void _attachFocusListener(int index) {
    _stops[index].focusNode.addListener(() {
      if (_stops[index].focusNode.hasFocus) {
        setState(() => _activeField = index);
      }
    });
  }

  Future<void> _loadMapStyle() async {
    final isNight = ref.read(mapNightProvider);
    final style = await rootBundle.loadString(MapTheme.styleAssetFor(isNight));
    if (mounted) setState(() => _mapStyle = style);
  }

  Future<void> _toggleMapTheme() async {
    await ref.read(mapNightProvider.notifier).toggle();
    await _loadMapStyle();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pickupCtrl.dispose();
    _pickupFocus.dispose();
    for (final s in _stops) {
      s.dispose();
    }
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      setState(() => _searching = true);
      try {
        final results = await _placesService.autocomplete(
          query: query,
          sessionToken: _sessionToken,
        );
        if (mounted) {
          setState(() {
            _suggestions = results;
            _searching = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _suggestions = [];
            _searching = false;
          });
        }
      }
    });
  }

  Future<void> _selectSuggestion(Map<String, dynamic> place) async {
    final field = _activeField;
    final fmt = place['structured_formatting'] as Map<String, dynamic>?;
    final label =
        (fmt?['main_text'] as String?) ??
        (place['description'] as String? ?? '');
    setState(() => _suggestions = []);
    try {
      final details = await _placesService.details(
        placeId: place['place_id'] as String,
        sessionToken: _sessionToken,
      );
      final loc = details?['geometry']?['location'] as Map<String, dynamic>?;
      final lat = (loc?['lat'] as num?)?.toDouble();
      final lng = (loc?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      _sessionToken = PlacesAutocompleteService.newSessionToken();

      if (!mounted) return;
      setState(() {
        if (field == 'pickup') {
          _pickupCtrl.text = label;
          _pickupLat = lat;
          _pickupLng = lng;
        } else if (field is int) {
          _stops[field].addressCtrl.text = label;
          _stops[field].lat = lat;
          _stops[field].lng = lng;
        }
        _activeField = null;
      });
      FocusScope.of(context).unfocus();
      _updateEstimate();
      _fitMapToMarkers();
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    }
  }

  Future<void> _fitMapToMarkers() async {
    final controller = _mapController;
    if (controller == null) return;
    final points = <LatLng>[
      if (_pickupLat != null) LatLng(_pickupLat!, _pickupLng!),
      for (final s in _stops)
        if (s.lat != null) LatLng(s.lat!, s.lng!),
    ];
    if (points.length < 2) return;
    final lats = points.map((p) => p.latitude);
    final lngs = points.map((p) => p.longitude);
    final bounds = LatLngBounds(
      southwest: LatLng(
        lats.reduce((a, b) => a < b ? a : b),
        lngs.reduce((a, b) => a < b ? a : b),
      ),
      northeast: LatLng(
        lats.reduce((a, b) => a > b ? a : b),
        lngs.reduce((a, b) => a > b ? a : b),
      ),
    );
    await controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 72));
  }

  void _addStop() {
    if (_stops.length >= _kMaxStops) return;
    final entry = _StopEntry();
    setState(() => _stops.add(entry));
    _attachFocusListener(_stops.length - 1);
  }

  void _removeStop(int index) {
    if (_stops.length <= _kMinStops) return;
    setState(() {
      _stops[index].dispose();
      _stops.removeAt(index);
      _estimate = null;
    });
    _updateEstimate();
  }

  bool get _readyForEstimate =>
      _pickupLat != null &&
      _stops.length >= _kMinStops &&
      _stops.every((s) => s.lat != null && s.lng != null);

  Future<void> _updateEstimate() async {
    if (!_readyForEstimate) {
      setState(() {
        _estimate = null;
        _estimateError = null;
      });
      return;
    }
    setState(() {
      _estimating = true;
      _estimateError = null;
    });
    try {
      final result = await _repo.estimateBatch(
        pickupLatitude: _pickupLat!,
        pickupLongitude: _pickupLng!,
        stops: _stops
            .map(
              (s) => {
                'deliveryAddress': s.addressCtrl.text,
                'deliveryLatitude': s.lat,
                'deliveryLongitude': s.lng,
              },
            )
            .toList(),
      );
      if (mounted) {
        setState(() {
          _estimate = result;
          _estimating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _estimateError = friendlyError(e);
          _estimating = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_estimate == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      final batch = await _repo.createBatch({
        'pickupAddress': _pickupCtrl.text.trim(),
        'pickupLatitude': _pickupLat,
        'pickupLongitude': _pickupLng,
        'stops': _stops
            .map(
              (s) => {
                'deliveryAddress': s.addressCtrl.text.trim(),
                'deliveryLatitude': s.lat,
                'deliveryLongitude': s.lng,
                if (s.receiverNameCtrl.text.trim().isNotEmpty)
                  'receiverName': s.receiverNameCtrl.text.trim(),
                if (s.receiverPhoneCtrl.text.trim().isNotEmpty)
                  'receiverPhone': '+221${s.receiverPhoneCtrl.text.trim()}',
              },
            )
            .toList(),
      });
      if (!mounted) return;
      showDemToast(context, 'Tournée créée — recherche d\'un livreur…');
      context.pushReplacement('/orders/batch/mine/${batch['id']}');
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{
      if (_pickupLat != null)
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(_pickupLat!, _pickupLng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: 'Collecte'),
        ),
      for (var i = 0; i < _stops.length; i++)
        if (_stops[i].lat != null)
          Marker(
            markerId: MarkerId('stop-$i'),
            position: LatLng(_stops[i].lat!, _stops[i].lng!),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueRed,
            ),
            infoWindow: InfoWindow(title: 'Arrêt ${i + 1}'),
          ),
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: _dakar,
                zoom: 12,
              ),
              onMapCreated: (c) => _mapController = c,
              style: _mapStyle,
              markers: markers,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new,
                        color: AppColors.textDark,
                        size: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Livraison groupée',
                    style: ClientText.subtitle.copyWith(
                      color: Colors.white,
                      shadows: const [
                        Shadow(color: Colors.black45, blurRadius: 6),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 16,
            child: MapThemeToggleButton(onTap: _toggleMapTheme, size: 44),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.72,
              ),
              decoration: const BoxDecoration(
                gradient: AppColors.gradientSplash,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20)],
              ),
              // `SingleChildScrollView` : le contenu s'adapte à l'espace
              // restant plutôt que de reposer sur un budget de hauteur fixe
              // (source répétée d'overflow ailleurs dans l'app) — quand le
              // clavier s'ouvre, il défile simplement, jamais de débordement.
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Text(
                        '1 collecte, jusqu\'à $_kMaxStops destinations — -20% sur le total.',
                        style: ClientText.body.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: 14),
                      AddressField(
                        controller: _pickupCtrl,
                        focusNode: _pickupFocus,
                        hint: 'Adresse de collecte',
                        dotColor: AppColors.success,
                        active: _activeField == 'pickup',
                        confirmed: _pickupLat != null,
                        onTap: () {
                          setState(() => _activeField = 'pickup');
                          _pickupFocus.requestFocus();
                        },
                        onChanged: _onQueryChanged,
                        onClear: () {
                          setState(() {
                            _pickupCtrl.clear();
                            _pickupLat = null;
                            _pickupLng = null;
                            _estimate = null;
                          });
                        },
                      ),
                      if (_activeField == 'pickup' &&
                          (_suggestions.isNotEmpty || _searching))
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: PlaceSuggestionsList(
                            suggestions: _suggestions,
                            loading: _searching,
                            colors: _placeSuggestionsColors,
                            onSelect: _selectSuggestion,
                          ),
                        ),
                      const SizedBox(height: 14),
                      Text(
                        'Destinations (${_stops.length}/$_kMaxStops)',
                        style: ClientText.bodyStrong.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _stops.length; i++) ...[
                        _StopCard(
                          index: i,
                          entry: _stops[i],
                          canRemove: _stops.length > _kMinStops,
                          onRemove: () => _removeStop(i),
                          onQueryChanged: _onQueryChanged,
                          active: _activeField == i,
                        ),
                        if (_activeField == i &&
                            (_suggestions.isNotEmpty || _searching))
                          Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 6),
                            child: PlaceSuggestionsList(
                              suggestions: _suggestions,
                              loading: _searching,
                              colors: _placeSuggestionsColors,
                              onSelect: _selectSuggestion,
                            ),
                          ),
                        const SizedBox(height: 10),
                      ],
                      if (_stops.length < _kMaxStops)
                        Pressable(
                          onTap: _addStop,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.add,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Ajouter un arrêt',
                                  style: ClientText.body.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      _PriceSummary(
                        estimate: _estimate,
                        estimating: _estimating,
                        error: _estimateError,
                        ready: _readyForEstimate,
                      ),
                      const SizedBox(height: 14),
                      PrimaryButton(
                        label: _estimate != null
                            ? 'Confirmer — ${formatFcfa((_estimate!['total'] as num).toInt())}'
                            : 'Confirmer la tournée',
                        onTap: (_estimate != null && !_submitting)
                            ? _submit
                            : null,
                        loading: _submitting,
                        color: _kBatchAccent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StopCard extends StatelessWidget {
  final int index;
  final _StopEntry entry;
  final bool canRemove;
  final bool active;
  final VoidCallback onRemove;
  final ValueChanged<String> onQueryChanged;
  const _StopCard({
    required this.index,
    required this.entry,
    required this.canRemove,
    required this.active,
    required this.onRemove,
    required this.onQueryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Arrêt ${index + 1}',
                style: ClientText.body.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              if (canRemove)
                GestureDetector(
                  onTap: onRemove,
                  child: const Icon(
                    Icons.close,
                    color: Colors.white38,
                    size: 16,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          AddressField(
            controller: entry.addressCtrl,
            focusNode: entry.focusNode,
            hint: 'Adresse de destination',
            dotColor: AppColors.error,
            active: active,
            confirmed: entry.lat != null,
            onTap: entry.focusNode.requestFocus,
            onChanged: onQueryChanged,
            onClear: () => entry.addressCtrl.clear(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: entry.receiverNameCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Destinataire (optionnel)',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                    border: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: entry.receiverPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Téléphone (optionnel)',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                    border: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PriceSummary extends StatelessWidget {
  final Map<String, dynamic>? estimate;
  final bool estimating;
  final String? error;
  final bool ready;
  const _PriceSummary({
    required this.estimate,
    required this.estimating,
    required this.error,
    required this.ready,
  });

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white38, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Renseignez la collecte et au moins $_kMinStops destinations pour voir le prix.',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }
    if (estimating) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: CircularProgressIndicator(
            color: _kBatchAccent,
            strokeWidth: 2,
          ),
        ),
      );
    }
    if (error != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          error!,
          style: const TextStyle(color: AppColors.error, fontSize: 12),
        ),
      );
    }
    if (estimate == null) return const SizedBox.shrink();

    final rawTotal = (estimate!['rawTotal'] as num).toInt();
    final discount = (estimate!['discountAmount'] as num).toInt();
    final total = (estimate!['total'] as num).toInt();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kBatchAccent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBatchAccent.withValues(alpha: 0.40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Total tournée',
                style: ClientText.body.copyWith(color: Colors.white70),
              ),
              const Spacer(),
              if (discount > 0)
                Text(
                  formatFcfa(rawTotal),
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 13,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                formatFcfa(total),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (discount > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Vous économisez ${formatFcfa(discount)} en groupant vos livraisons',
              style: const TextStyle(
                color: _kBatchAccent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
