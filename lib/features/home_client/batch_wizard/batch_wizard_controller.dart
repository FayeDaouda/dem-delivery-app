import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/error/app_exception.dart';
import '../../../core/map/route_marker_icons.dart';
import '../../../core/services/location_reveal_controller.dart';
import '../../../core/services/places_autocomplete_service.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dem_toast.dart';
import '../../../shared/widgets/address_options_sheet.dart';
import '../../../shared/widgets/contact_picker.dart';
import '../../../shared/widgets/favorite_address_chips.dart';
import '../../../shared/widgets/map_placement_pin.dart';
import '../../client_profile/data/favorite_addresses_repository.dart';
import '../../deliveries/data/orders_repository.dart';
import '../../home_driver/navigation/navigation_service.dart';
import '../map_host.dart';
import 'batch_wizard_steps.dart';

const int kBatchMinStops = 2;
const int kBatchMaxStops = 3;

/// Un arrêt de la tournée — collecte unique, jusqu'à [kBatchMaxStops]
/// destinations. Publique (contrairement à l'ancienne `_StopEntry` privée de
/// batch_create_screen.dart) : batch_wizard_steps.dart en a besoin pour ses
/// widgets de présentation.
class BatchStopEntry {
  final addressCtrl = TextEditingController();
  final receiverNameCtrl = TextEditingController();
  final receiverPhoneCtrl = TextEditingController();
  final focusNode = FocusNode();
  double? lat;
  double? lng;
  bool manualEntry = false;

  void dispose() {
    addressCtrl.dispose();
    receiverNameCtrl.dispose();
    receiverPhoneCtrl.dispose();
    focusNode.dispose();
  }
}

bool validateBatchPhone(
  BuildContext context,
  TextEditingController ctrl,
  String label,
) {
  final digits = ctrl.text.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) {
    showDemToast(context, 'Numéro $label requis', isError: true);
    return false;
  }
  if (digits.length < 9) {
    showDemToast(
      context,
      'Numéro $label invalide — 9 chiffres minimum',
      isError: true,
    );
    return false;
  }
  return true;
}

/// Logique du parcours Groupée — extraite quasi telle quelle de l'ancien
/// batch_create_screen.dart, sur le même modèle que OrderWizardController
/// (voir order_wizard_controller.dart) : plus de carte/GPS/style propres
/// (voir MapHost, fourni par ClientHomeShellScreen), uniquement la logique de
/// formulaire (étapes, arrêts dynamiques, contacts, prix, soumission).
///
/// Instancié une seule fois par ClientHomeShellScreen puis CONSERVÉ tant que
/// la tournée n'est pas soumise (même décision produit que Express/Simple :
/// la saisie en cours survit à un aller-retour vers l'accueil).
class BatchWizardController {
  BatchWizardController({
    required this.mapHost,
    required this.onChanged,
    required this.onSubmitSuccess,
    required TickerProvider vsync,
  }) : pickupReveal = LocationRevealController(
         vsync: vsync,
         onUpdate: onChanged,
       ) {
    _init();
  }

  final MapHost mapHost;

  /// Appelé après chaque mutation d'état — le socle y répond par un simple
  /// `setState(() {})`.
  final VoidCallback onChanged;

  /// Signalé une fois la tournée créée avec succès — le socle en profite pour
  /// repasser en mode accueil et détruire ce contrôleur.
  final VoidCallback onSubmitSuccess;

  final _repo = OrdersRepository();

  // ── Step wizard ──────────────────────────────────────────────────────────
  int step = 0; // 0=Trajet, 1=Expéditeur, 2=Destinataires, 3=Résumé

  // ── Placement mode ───────────────────────────────────────────────────────
  // 'pickup' ou l'index (int) d'un arrêt — même convention que activeField.
  Object? activeField;
  bool isMapPlacementMode = false;

  // ── Collecte ─────────────────────────────────────────────────────────────
  final pickupCtrl = TextEditingController();
  final pickupFocus = FocusNode();
  double? pickupLat, pickupLng;
  bool pickupManualEntry = false;
  bool loadingGps = false;

  // ── Arrêts ───────────────────────────────────────────────────────────────
  final List<BatchStopEntry> stops = [BatchStopEntry(), BatchStopEntry()];

  // ── Expéditeur ───────────────────────────────────────────────────────────
  final senderNameCtrl = TextEditingController();
  final senderPhoneCtrl = TextEditingController();

  // ── Autocomplete ─────────────────────────────────────────────────────────
  List<Map<String, dynamic>> suggestions = [];
  bool isSearching = false;
  String? searchError;
  String? _sessionToken;
  Timer? _searchDebounce;

  // ── Estimation / soumission ─────────────────────────────────────────────
  Map<String, dynamic>? estimate;
  bool estimating = false;
  String? estimateError;
  bool submitting = false;
  Timer? _estimateDebounce;

  Map<String, dynamic>? currentUser;

  late final _publicDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );
  late final _placesService = PlacesAutocompleteService(_publicDio);

  final _favRepo = FavoriteAddressesRepository();
  List<Map<String, dynamic>> favorites = [];

  BitmapDescriptor? _pickupIcon;
  BitmapDescriptor? _stopIcon;

  // Chute + rebond du marqueur de collecte à l'arrivée sur l'étape Trajet —
  // même mécanique que Express/Simple (cohérence visuelle entre les 2 modes,
  // voir OrderWizardController.pickupReveal), vsync fourni par le socle.
  final LocationRevealController pickupReveal;

  ScreenCoordinate? pickupScreenPos;
  LatLng? _pickupScreenPosSource;

  /// Recalcule sans condition — nécessaire après un pan/zoom manuel ou une
  /// animation de caméra (voir OrderWizardController.forceUpdatePickupScreenPos,
  /// même raison). Utilisé par le socle sur `onCameraIdle`.
  Future<void> forceUpdatePickupScreenPos(LatLng target) async {
    final controller = mapHost.mapController;
    if (controller == null) return;
    final coord = await controller.getScreenCoordinate(target);
    pickupScreenPos = coord;
    onChanged();
  }

  /// À appeler à chaque frame par le socle — ne recalcule que si le POINT
  /// suivi a changé (pas la caméra).
  void maybeUpdatePickupScreenPos(LatLng current) {
    if (_pickupScreenPosSource == current) return;
    _pickupScreenPosSource = current;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => forceUpdatePickupScreenPos(current),
    );
  }

  void _init() {
    _seedInitialPickup();
    _loadUser();
    _loadFavorites();
    _loadMarkerIcons();
    for (var i = 0; i < stops.length; i++) {
      _attachStopFocusListener(i);
    }
  }

  Future<void> _loadMarkerIcons() async {
    final results = await Future.wait([
      RouteMarkerIcons.pickup(AppColors.success),
      RouteMarkerIcons.delivery(AppColors.error),
    ]);
    _pickupIcon = results[0];
    _stopIcon = results[1];
    onChanged();
  }

  Future<void> _loadFavorites() async {
    try {
      final list = await _favRepo.getAll();
      favorites = list;
      onChanged();
    } catch (_) {}
  }

  Future<void> _loadUser() async {
    final user = await AuthStorage.getUser();
    currentUser = user;
    onChanged();
  }

  void _attachStopFocusListener(int index) {
    stops[index].focusNode.addListener(() {
      if (stops[index].focusNode.hasFocus) {
        activeField = index;
        onChanged();
      }
    });
  }

  void fillMe(TextEditingController nameCtrl, TextEditingController phoneCtrl) {
    if (currentUser != null) {
      nameCtrl.text = currentUser!['name'] ?? currentUser!['firstName'] ?? '';
      phoneCtrl.text = (currentUser!['phone'] ?? '').replaceFirst('+221', '');
    }
  }

  void dispose() {
    pickupReveal.dispose();
    _searchDebounce?.cancel();
    _estimateDebounce?.cancel();
    pickupCtrl.dispose();
    pickupFocus.dispose();
    senderNameCtrl.dispose();
    senderPhoneCtrl.dispose();
    for (final s in stops) {
      s.dispose();
    }
  }

  // ── GPS ──────────────────────────────────────────────────────────────────
  // Même logique de continuité que OrderWizardController._seedInitialPickup :
  // reprend la position déjà connue du socle SANS déplacer la caméra — c'est
  // justement ce qui cassait la continuité "une seule carte" avant la fusion.
  Future<void> _seedInitialPickup() async {
    final known = mapHost.currentPosition;
    if (known != null) {
      pickupLat = known.latitude;
      pickupLng = known.longitude;
      pickupReveal.reveal();
      onChanged();
      await _reverseGeocode(known, forPickup: true);
      return;
    }
    loadingGps = true;
    onChanged();
    try {
      final pos = await NavigationService.requestAndGetPosition();
      if (pos != null) {
        final ll = LatLng(pos.latitude, pos.longitude);
        mapHost.centerOn(ll);
        pickupLat = ll.latitude;
        pickupLng = ll.longitude;
        pickupReveal.reveal();
        await _reverseGeocode(ll, forPickup: true);
      }
    } catch (_) {
    } finally {
      loadingGps = false;
      onChanged();
    }
  }

  /// Recentrage explicite (bouton "ma position") — DOIT déplacer la caméra,
  /// contrairement à la saisie initiale silencieuse ci-dessus.
  Future<void> refreshGps() async {
    loadingGps = true;
    onChanged();
    try {
      final pos = await NavigationService.requestAndGetPosition();
      if (pos != null) {
        final ll = LatLng(pos.latitude, pos.longitude);
        mapHost.centerOn(ll);
        pickupLat = ll.latitude;
        pickupLng = ll.longitude;
        pickupReveal.reveal();
        await _reverseGeocode(ll, forPickup: true);
      }
    } catch (_) {
    } finally {
      loadingGps = false;
      onChanged();
    }
  }

  Future<void> _reverseGeocode(LatLng pos, {required bool forPickup}) async {
    final label = await _reverseGeocodeLabel(pos);
    if (forPickup) {
      pickupCtrl.text = label;
    }
    onChanged();
  }

  Future<String> _reverseGeocodeLabel(LatLng pos) async {
    String? addr = await _placesService.reverseGeocode(
      pos.latitude,
      pos.longitude,
    );
    if (addr == null || addr.isEmpty) {
      try {
        final marks = await geo
            .placemarkFromCoordinates(pos.latitude, pos.longitude)
            .timeout(const Duration(seconds: 5));
        if (marks.isNotEmpty) {
          final p = marks.first;
          final street = p.street ?? p.name ?? '';
          final local = p.subLocality ?? p.locality ?? '';
          final built = street.isNotEmpty ? '$street, $local' : local;
          if (built.isNotEmpty) addr = built;
        }
      } catch (_) {}
    }
    return (addr != null && addr.isNotEmpty) ? addr : 'Position sélectionnée';
  }

  // Position actuelle pour la collecte OU un arrêt donné — 'pickup' ou un
  // index int, même convention que OrderWizardController.
  Future<void> useCurrentLocationFor(Object field, BuildContext context) async {
    if (field == 'pickup') {
      loadingGps = true;
      onChanged();
    }
    try {
      final pos = await NavigationService.requestAndGetPosition();
      if (pos == null) return;
      final ll = LatLng(pos.latitude, pos.longitude);
      final label = await _reverseGeocodeLabel(ll);
      if (field == 'pickup') {
        pickupLat = ll.latitude;
        pickupLng = ll.longitude;
        pickupCtrl.text = label;
        pickupManualEntry = false;
      } else if (field is int) {
        stops[field].lat = ll.latitude;
        stops[field].lng = ll.longitude;
        stops[field].addressCtrl.text = label;
        stops[field].manualEntry = false;
      }
      onChanged();
      _updateEstimate();
      _fitPointsToKnown();
    } catch (_) {
      if (context.mounted) {
        showDemToast(
          context,
          'Impossible de récupérer la position.',
          isError: true,
        );
      }
    } finally {
      if (field == 'pickup') {
        loadingGps = false;
        onChanged();
      }
    }
  }

  Future<void> showAddressMenu(Object field, BuildContext context) async {
    final choice = await showAddressOptionsSheet(
      context,
      forPickup: field == 'pickup',
    );
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case AddressOptionChoice.currentLocation:
        await useCurrentLocationFor(field, context);
      case AddressOptionChoice.favorites:
        final fav = await pickFavoriteAddress(
          context,
          favorites: favorites,
          forPickup: field == 'pickup',
        );
        if (fav == null) return;
        activeField = field;
        applyFavorite(fav);
      case AddressOptionChoice.map:
        enterMapPlacement(field);
      case AddressOptionChoice.manual:
        activeField = field;
        if (field == 'pickup') {
          pickupManualEntry = true;
        } else if (field is int) {
          stops[field].manualEntry = true;
        }
        onChanged();
        if (field == 'pickup') {
          pickupFocus.requestFocus();
        } else if (field is int) {
          stops[field].focusNode.requestFocus();
        }
    }
  }

  void applyFavorite(Map<String, dynamic> fav) {
    final field = activeField;
    final lat = (fav['lat'] as num).toDouble();
    final lng = (fav['lng'] as num).toDouble();
    final addr = fav['address'] as String;
    if (field == 'pickup') {
      pickupCtrl.text = addr;
      pickupLat = lat;
      pickupLng = lng;
    } else if (field is int) {
      stops[field].addressCtrl.text = addr;
      stops[field].lat = lat;
      stops[field].lng = lng;
    }
    suggestions = [];
    activeField = null;
    onChanged();
    mapHost.centerOn(LatLng(lat, lng));
    _updateEstimate();
    _fitPointsToKnown();
  }

  // ── Mode "pointer sur la carte" ──────────────────────────────────────────
  void enterMapPlacement(Object field) {
    double? lat, lng;
    if (field == 'pickup') {
      lat = pickupLat;
      lng = pickupLng;
    } else if (field is int) {
      lat = stops[field].lat;
      lng = stops[field].lng;
    }
    if (lat != null && lng != null) {
      mapHost.centerOn(LatLng(lat, lng), zoom: 16);
    }
    activeField = field;
    isMapPlacementMode = true;
    onChanged();
  }

  Future<void> confirmPlacement() async {
    final field = activeField;
    final pos = mapHost.currentCameraPosition;
    isMapPlacementMode = false;
    if (field == 'pickup') {
      pickupLat = pos.latitude;
      pickupLng = pos.longitude;
    } else if (field is int) {
      stops[field].lat = pos.latitude;
      stops[field].lng = pos.longitude;
    }
    onChanged();
    final label = await _reverseGeocodeLabel(pos);
    if (field == 'pickup') {
      pickupCtrl.text = label;
    } else if (field is int) {
      stops[field].addressCtrl.text = label;
    }
    onChanged();
    _updateEstimate();
    _fitPointsToKnown();
  }

  // ── Autocomplete Google Places ────────────────────────────────────────────
  void onQueryChanged(String query, Object field) {
    activeField = field;
    _searchDebounce?.cancel();
    if (query.trim().length < 3) {
      suggestions = [];
      onChanged();
      return;
    }
    onChanged();
    _sessionToken ??= PlacesAutocompleteService.newSessionToken();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () async {
      isSearching = true;
      searchError = null;
      onChanged();
      try {
        final results = await _placesService.autocomplete(
          query: query,
          sessionToken: _sessionToken!,
        );
        suggestions = results;
        isSearching = false;
        onChanged();
      } catch (e) {
        suggestions = [];
        isSearching = false;
        searchError = friendlyError(e);
        onChanged();
      }
    });
  }

  Future<void> selectSuggestion(
    Map<String, dynamic> place,
    BuildContext context,
  ) async {
    final field = activeField;
    final fmt = place['structured_formatting'] as Map<String, dynamic>?;
    final label =
        (fmt?['main_text'] as String?) ??
        (place['description'] as String? ?? '');
    suggestions = [];
    onChanged();
    try {
      final details = await _placesService.details(
        placeId: place['place_id'] as String,
        sessionToken:
            _sessionToken ?? PlacesAutocompleteService.newSessionToken(),
      );
      final loc = details?['geometry']?['location'] as Map<String, dynamic>?;
      final lat = (loc?['lat'] as num?)?.toDouble();
      final lng = (loc?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      _sessionToken = null;

      if (field == 'pickup') {
        pickupCtrl.text = label;
        pickupLat = lat;
        pickupLng = lng;
      } else if (field is int) {
        stops[field].addressCtrl.text = label;
        stops[field].lat = lat;
        stops[field].lng = lng;
      }
      activeField = null;
      onChanged();
      if (context.mounted) FocusScope.of(context).unfocus();
      mapHost.centerOn(LatLng(lat, lng));
      _updateEstimate();
      _fitPointsToKnown();
    } catch (e) {
      if (context.mounted)
        showDemToast(context, friendlyError(e), isError: true);
    }
  }

  void retryAddressSearch() {
    final field = activeField;
    final query = field == 'pickup'
        ? pickupCtrl.text
        : (field is int ? stops[field].addressCtrl.text : '');
    if (field != null) onQueryChanged(query, field);
  }

  // Cadre tous les points déjà connus (collecte + arrêts) — délègue au
  // MapHost partagé plutôt que de dupliquer le calcul de bornes ici (voir
  // ClientHomeShellScreen.fitPoints, généralisé lors de la fusion).
  void _fitPointsToKnown() {
    final points = <LatLng>[
      if (pickupLat != null) LatLng(pickupLat!, pickupLng!),
      for (final s in stops)
        if (s.lat != null) LatLng(s.lat!, s.lng!),
    ];
    if (points.length < 2) return;
    mapHost.fitPoints(points);
  }

  // ── Arrêts dynamiques ────────────────────────────────────────────────────
  // Le socle remesure la feuille après chaque ajout/retrait (voir onChanged
  // + mapHost.requestSheetRemeasure) — point d'attention particulier du plan
  // de fusion : une liste dynamique de 2-3 cartes doit rester en phase avec
  // AnimatedSize sans jamais tronquer la dernière carte ajoutée.
  void addStop() {
    if (stops.length >= kBatchMaxStops) return;
    stops.add(BatchStopEntry());
    _attachStopFocusListener(stops.length - 1);
    onChanged();
    mapHost.requestSheetRemeasure();
  }

  void removeStop(int index) {
    if (stops.length <= kBatchMinStops) return;
    stops[index].dispose();
    stops.removeAt(index);
    estimate = null;
    onChanged();
    mapHost.requestSheetRemeasure();
    _updateEstimate();
  }

  void clearStop(int index) {
    stops[index].addressCtrl.clear();
    stops[index].lat = null;
    stops[index].lng = null;
    stops[index].manualEntry = false;
    estimate = null;
    onChanged();
  }

  void clearPickup() {
    pickupCtrl.clear();
    pickupLat = null;
    pickupLng = null;
    estimate = null;
    pickupManualEntry = false;
    onChanged();
  }

  bool get readyForEstimate =>
      pickupLat != null &&
      stops.length >= kBatchMinStops &&
      stops.every((s) => s.lat != null && s.lng != null);

  void _updateEstimate() {
    _estimateDebounce?.cancel();
    if (!readyForEstimate) {
      estimate = null;
      estimateError = null;
      onChanged();
      return;
    }
    _estimateDebounce = Timer(
      const Duration(milliseconds: 800),
      _computeEstimate,
    );
  }

  Future<void> _computeEstimate() async {
    if (!readyForEstimate) return;
    estimating = true;
    estimateError = null;
    onChanged();
    try {
      final result = await _repo.estimateBatch(
        pickupLatitude: pickupLat!,
        pickupLongitude: pickupLng!,
        stops: stops
            .map(
              (s) => {
                'deliveryAddress': s.addressCtrl.text,
                'deliveryLatitude': s.lat,
                'deliveryLongitude': s.lng,
              },
            )
            .toList(),
      );
      estimate = result;
      estimating = false;
      onChanged();
    } catch (e) {
      estimateError = friendlyError(e);
      estimating = false;
      onChanged();
    }
  }

  void retryEstimate() {
    estimateError = null;
    onChanged();
    _updateEstimate();
  }

  // ── Step navigation ───────────────────────────────────────────────────────
  void goStep(int newStep, BuildContext context) {
    FocusScope.of(context).unfocus();
    step = newStep;
    onChanged();
    mapHost.requestSheetRemeasure();
    if (newStep >= 1) _fitPointsToKnown();
  }

  /// Contenu de l'étape courante — la Key distincte déclenche la transition
  /// d'AnimatedSwitcher côté HomeClientSheetScaffold.
  Widget buildStep(BuildContext context) {
    final Widget child;
    if (isMapPlacementMode) {
      child = MapPlacementConfirmPanel(
        color: activeField == 'pickup' ? AppColors.success : AppColors.error,
        label: activeField == 'pickup'
            ? 'Valider ce point de collecte'
            : 'Valider ce point de destination',
        onConfirm: confirmPlacement,
      );
    } else {
      switch (step) {
        case 0:
          child = BatchStep0Panel(
            pickupCtrl: pickupCtrl,
            pickupFocus: pickupFocus,
            pickupConfirmed: pickupLat != null,
            pickupManualEntry: pickupManualEntry,
            stops: stops,
            activeField: activeField,
            suggestions: suggestions,
            searching: isSearching,
            searchError: searchError,
            favorites: favorites,
            onSelectFavorite: applyFavorite,
            onPickupTap: () {
              if (!pickupManualEntry) {
                showAddressMenu('pickup', context);
                return;
              }
              activeField = 'pickup';
              onChanged();
              pickupFocus.requestFocus();
            },
            onStopTap: (i) {
              if (!stops[i].manualEntry) {
                showAddressMenu(i, context);
                return;
              }
              activeField = i;
              onChanged();
              stops[i].focusNode.requestFocus();
            },
            onQueryChanged: (q) => onQueryChanged(q, activeField ?? 'pickup'),
            onSelectSuggestion: (p) => selectSuggestion(p, context),
            onRetryAddressSearch: retryAddressSearch,
            onPickupClear: clearPickup,
            onAddStop: addStop,
            onRemoveStop: removeStop,
            onClearStop: clearStop,
            onNext: () => goStep(1, context),
            canNext: readyForEstimate,
          );
        case 1:
          child = BatchStep1Panel(
            nameCtrl: senderNameCtrl,
            phoneCtrl: senderPhoneCtrl,
            onPickContact: () => pickContact(
              context,
              nameCtrl: senderNameCtrl,
              phoneCtrl: senderPhoneCtrl,
            ),
            onPickMe: () {
              fillMe(senderNameCtrl, senderPhoneCtrl);
              if (senderPhoneCtrl.text.length >= 9) goStep(2, context);
            },
            onNext: () {
              if (!validateBatchPhone(context, senderPhoneCtrl, 'expéditeur')) {
                return;
              }
              goStep(2, context);
            },
          );
        case 2:
          child = BatchStep2Panel(
            stops: stops,
            onNext: () {
              for (var i = 0; i < stops.length; i++) {
                if (!validateBatchPhone(
                  context,
                  stops[i].receiverPhoneCtrl,
                  'destinataire — arrêt ${i + 1}',
                )) {
                  return;
                }
              }
              goStep(3, context);
            },
          );
        default:
          child = BatchStep3Panel(
            pickupLabel: pickupCtrl.text,
            stops: stops,
            estimate: estimate,
            estimating: estimating,
            error: estimateError,
            ready: readyForEstimate,
            submitting: submitting,
            onEditTrajet: () => goStep(0, context),
            onSubmit: () => submit(context),
          );
      }
    }
    return KeyedSubtree(
      key: ValueKey(isMapPlacementMode ? 'batch-placement' : 'batch-$step'),
      child: child,
    );
  }

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> submit(BuildContext context) async {
    if (estimate == null || submitting) return;
    submitting = true;
    onChanged();
    try {
      final batch = await _repo.createBatch({
        'pickupAddress': pickupCtrl.text.trim(),
        'pickupLatitude': pickupLat,
        'pickupLongitude': pickupLng,
        if (senderNameCtrl.text.trim().isNotEmpty)
          'senderName': senderNameCtrl.text.trim(),
        if (senderPhoneCtrl.text.trim().isNotEmpty)
          'senderPhone': '+221${senderPhoneCtrl.text.trim()}',
        'stops': stops
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
      if (!context.mounted) return;
      context.pushReplacement('/orders/batch/confirmation', extra: batch);
      onSubmitSuccess();
    } catch (e) {
      if (context.mounted)
        showDemToast(context, friendlyError(e), isError: true);
    } finally {
      submitting = false;
      onChanged();
    }
  }

  // ── Carte : marqueurs ────────────────────────────────────────────────────
  Set<Marker> get markers {
    final result = <Marker>{};
    if (pickupLat != null && (activeField != 'pickup' || !isMapPlacementMode)) {
      result.add(
        Marker(
          markerId: const MarkerId('batch-pickup'),
          position: pickupReveal.markerPosition(LatLng(pickupLat!, pickupLng!)),
          icon:
              _pickupIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          anchor: _pickupIcon != null
              ? const Offset(0.5, 0.5)
              : const Offset(0.5, 1.0),
          infoWindow: const InfoWindow(title: 'Collecte'),
          onTap: () {
            activeField = 'pickup';
            isMapPlacementMode = true;
            onChanged();
            mapHost.centerOn(LatLng(pickupLat!, pickupLng!));
          },
        ),
      );
    }
    for (var i = 0; i < stops.length; i++) {
      final s = stops[i];
      if (s.lat == null) continue;
      if (activeField == i && isMapPlacementMode) continue;
      result.add(
        Marker(
          markerId: MarkerId('batch-stop-$i'),
          position: LatLng(s.lat!, s.lng!),
          icon:
              _stopIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          anchor: _stopIcon != null
              ? RouteMarkerIcons.pinAnchor
              : const Offset(0.5, 1.0),
          infoWindow: InfoWindow(title: 'Arrêt ${i + 1}'),
          onTap: () {
            activeField = i;
            isMapPlacementMode = true;
            onChanged();
            mapHost.centerOn(LatLng(s.lat!, s.lng!));
          },
        ),
      );
    }
    return result;
  }

  // Pas de tracé multi-arrêts pour l'instant (hors périmètre de la fusion,
  // déjà le cas sur l'ancien batch_create_screen.dart).
  Set<Polyline> get polylines => const {};
}
