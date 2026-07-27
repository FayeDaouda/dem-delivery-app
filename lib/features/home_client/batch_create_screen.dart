import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/error/app_exception.dart';
import '../../core/services/places_autocomplete_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../../core/utils/dem_toast.dart';
import '../../core/utils/price_format.dart';
import '../../shared/widgets/place_suggestions_list.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/primary_button.dart';
import '../deliveries/data/orders_repository.dart';

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

const int _kMinStops = 2;
const int _kMaxStops = 3;

class _StopEntry {
  final _addressCtrl = TextEditingController();
  final _receiverNameCtrl = TextEditingController();
  final _receiverPhoneCtrl = TextEditingController();
  final _focusNode = FocusNode();
  double? lat;
  double? lng;

  void dispose() {
    _addressCtrl.dispose();
    _receiverNameCtrl.dispose();
    _receiverPhoneCtrl.dispose();
    _focusNode.dispose();
  }
}

class BatchCreateScreen extends StatefulWidget {
  const BatchCreateScreen({super.key});

  @override
  State<BatchCreateScreen> createState() => _BatchCreateScreenState();
}

class _BatchCreateScreenState extends State<BatchCreateScreen> {
  final _repo = OrdersRepository();

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
    _pickupFocus.addListener(() {
      if (_pickupFocus.hasFocus) setState(() => _activeField = 'pickup');
    });
    for (var i = 0; i < _stops.length; i++) {
      final idx = i;
      _stops[i]._focusNode.addListener(() {
        if (_stops[idx]._focusNode.hasFocus) setState(() => _activeField = idx);
      });
    }
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
        if (mounted)
          setState(() {
            _suggestions = results;
            _searching = false;
          });
      } catch (_) {
        if (mounted)
          setState(() {
            _suggestions = [];
            _searching = false;
          });
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
          _stops[field]._addressCtrl.text = label;
          _stops[field].lat = lat;
          _stops[field].lng = lng;
        }
        _activeField = null;
      });
      FocusScope.of(context).unfocus();
      _updateEstimate();
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    }
  }

  void _addStop() {
    if (_stops.length >= _kMaxStops) return;
    final entry = _StopEntry();
    final idx = _stops.length;
    entry._focusNode.addListener(() {
      if (entry._focusNode.hasFocus) setState(() => _activeField = idx);
    });
    setState(() => _stops.add(entry));
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
                'deliveryAddress': s._addressCtrl.text,
                'deliveryLatitude': s.lat,
                'deliveryLongitude': s.lng,
              },
            )
            .toList(),
      );
      if (mounted)
        setState(() {
          _estimate = result;
          _estimating = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _estimateError = friendlyError(e);
          _estimating = false;
        });
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
                'deliveryAddress': s._addressCtrl.text.trim(),
                'deliveryLatitude': s.lat,
                'deliveryLongitude': s.lng,
                if (s._receiverNameCtrl.text.trim().isNotEmpty)
                  'receiverName': s._receiverNameCtrl.text.trim(),
                if (s._receiverPhoneCtrl.text.trim().isNotEmpty)
                  'receiverPhone': '+221${s._receiverPhoneCtrl.text.trim()}',
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  Text(
                    'Livraison groupée',
                    style: ClientText.subtitle.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '1 point de collecte, jusqu\'à $_kMaxStops destinations — -20% sur le total.',
                style: ClientText.body.copyWith(color: Colors.white54),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  Text(
                    'Collecte',
                    style: ClientText.bodyStrong.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  _AddressField(
                    controller: _pickupCtrl,
                    focusNode: _pickupFocus,
                    hint: 'Adresse de collecte',
                    dotColor: AppColors.success,
                    onChanged: _onQueryChanged,
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
                  const SizedBox(height: 20),
                  Text(
                    'Destinations (${_stops.length}/$_kMaxStops)',
                    style: ClientText.bodyStrong.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _stops.length; i++) ...[
                    _StopCard(
                      index: i,
                      entry: _stops[i],
                      canRemove: _stops.length > _kMinStops,
                      onRemove: () => _removeStop(i),
                      onQueryChanged: _onQueryChanged,
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
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white24,
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.add,
                              color: _kBatchAccent,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Ajouter un arrêt',
                              style: ClientText.body.copyWith(
                                color: _kBatchAccent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  _PriceSummary(
                    estimate: _estimate,
                    estimating: _estimating,
                    error: _estimateError,
                    ready: _readyForEstimate,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: PrimaryButton(
                label: _estimate != null
                    ? 'Confirmer — ${formatFcfa((_estimate!['total'] as num).toInt())}'
                    : 'Confirmer la tournée',
                onTap: (_estimate != null && !_submitting) ? _submit : null,
                loading: _submitting,
                color: _kBatchAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final Color dotColor;
  final ValueChanged<String> onChanged;
  const _AddressField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.dotColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
  final VoidCallback onRemove;
  final ValueChanged<String> onQueryChanged;
  const _StopCard({
    required this.index,
    required this.entry,
    required this.canRemove,
    required this.onRemove,
    required this.onQueryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
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
          _AddressField(
            controller: entry._addressCtrl,
            focusNode: entry._focusNode,
            hint: 'Adresse de destination',
            dotColor: AppColors.error,
            onChanged: onQueryChanged,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: entry._receiverNameCtrl,
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
                  controller: entry._receiverPhoneCtrl,
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
          color: Colors.white.withValues(alpha: 0.04),
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
        color: _kBatchAccent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBatchAccent.withValues(alpha: 0.35)),
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
                  fontSize: 17,
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
