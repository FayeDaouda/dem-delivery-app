import 'dart:async';
import 'package:dio/dio.dart';
import '../../core/error/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/places_autocomplete_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../../core/utils/dem_toast.dart';
import '../../shared/widgets/place_suggestions_list.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/skeleton_loader.dart';
import 'data/favorite_addresses_repository.dart';

const _kIcons = ['📍', '🏠', '💼', '❤️', '🛒', '🏫', '🏥', '🕌', '⭐'];
// 3 emplacements au total : "Maison" et "Bureau" réservés (comme
// Uber/Bolt) + 1 adresse personnalisée nommée librement par le client.
const _kMax = 3;
const _kHomeLabel = 'Maison';
const _kWorkLabel = 'Bureau';

const _placeSuggestionsColors = PlaceSuggestionsColors(
  background: Colors.white,
  border: AppColors.lightBorder,
  divider: AppColors.lightBorder,
  iconBg: Color.fromRGBO(12, 184, 222, 0.08), // AppColors.primary à 8%
  icon: AppColors.primary,
  mainText: AppColors.textDark,
  secondaryText: AppColors.textMuted,
  accent: AppColors.primary,
  shadow: Color(0x14000000),
);

Map<String, dynamic>? _findByLabel(
  List<Map<String, dynamic>> list,
  String label,
) {
  for (final a in list) {
    if (a['label'] == label) return a;
  }
  return null;
}

class FavoriteAddressesScreen extends StatefulWidget {
  const FavoriteAddressesScreen({super.key});
  @override
  State<FavoriteAddressesScreen> createState() =>
      _FavoriteAddressesScreenState();
}

class _FavoriteAddressesScreenState extends State<FavoriteAddressesScreen> {
  final _repo = FavoriteAddressesRepository();
  List<Map<String, dynamic>> _addresses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final list = await _repo.getAll();
      if (mounted)
        setState(() {
          _addresses = list;
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({
    Map<String, dynamic>? existing,
    String? lockedLabel,
    String? defaultIcon,
  }) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddressFormSheet(
        existing: existing,
        lockedLabel: lockedLabel,
        defaultIcon: defaultIcon,
      ),
    );
    if (result == null || !mounted) return;
    try {
      if (existing == null) {
        final created = await _repo.create(result);
        setState(() => _addresses.add(created));
      } else {
        final updated = await _repo.update(existing['id'] as String, result);
        setState(() {
          final idx = _addresses.indexWhere((a) => a['id'] == existing['id']);
          if (idx >= 0) _addresses[idx] = updated;
        });
      }
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> addr) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Supprimer "${addr['label']}" ?', style: ClientText.button),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Supprimer',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.delete(addr['id'] as String);
      if (mounted)
        setState(() => _addresses.removeWhere((a) => a['id'] == addr['id']));
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = _findByLabel(_addresses, _kHomeLabel);
    final work = _findByLabel(_addresses, _kWorkLabel);
    final others = _addresses
        .where((a) => a['label'] != _kHomeLabel && a['label'] != _kWorkLabel)
        .toList();
    // "Garder l'existant, bloquer les nouvelles" — un compte créé avant ce
    // plafond de 3 peut avoir davantage d'adresses ; elles restent toutes
    // visibles/gérables ci-dessous, seule la création est bloquée au-delà.
    final canAddMore = _addresses.length < _kMax;

    return Scaffold(
      backgroundColor: AppColors.lightBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Adresses favorites',
                      style: ClientText.subtitle.copyWith(color: Colors.white),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
          ),

          // ── Corps ───────────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                    itemCount: 3,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, _) => const _AddressTileSkeleton(),
                  )
                : RefreshIndicator(
                    onRefresh: _fetch,
                    color: AppColors.primary,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                      children: [
                        Text(
                          'Emplacements rapides',
                          style: ClientText.label.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _SlotTile(
                          existing: home,
                          label: _kHomeLabel,
                          icon: '🏠',
                          onTap: () => _openForm(
                            existing: home,
                            lockedLabel: _kHomeLabel,
                            defaultIcon: '🏠',
                          ),
                          onDelete: home != null
                              ? () => _confirmDelete(home)
                              : null,
                        ),
                        const SizedBox(height: 10),
                        _SlotTile(
                          existing: work,
                          label: _kWorkLabel,
                          icon: '💼',
                          onTap: () => _openForm(
                            existing: work,
                            lockedLabel: _kWorkLabel,
                            defaultIcon: '💼',
                          ),
                          onDelete: work != null
                              ? () => _confirmDelete(work)
                              : null,
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Adresse personnalisée',
                          style: ClientText.label.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final addr in others) ...[
                          _AddressTile(
                            address: addr,
                            onEdit: () => _openForm(existing: addr),
                            onDelete: () => _confirmDelete(addr),
                          ),
                          const SizedBox(height: 10),
                        ],
                        if (canAddMore)
                          _AddCustomTile(onTap: () => _openForm()),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Skeleton (chargement) — épouse la forme de _AddressTile ─────────────────
class _AddressTileSkeleton extends StatelessWidget {
  const _AddressTileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            margin: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: AppColors.lightFill,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SkeletonBox(width: 120, height: 13),
                const SizedBox(height: 8),
                SkeletonBox(
                  width: MediaQuery.of(context).size.width * 0.4,
                  height: 11,
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
        ],
      ),
    );
  }
}

// ── Tile adresse ──────────────────────────────────────────────────────────────
class _AddressTile extends StatelessWidget {
  final Map<String, dynamic> address;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _AddressTile({
    required this.address,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          // Icône
          GestureDetector(
            onTap: onEdit,
            child: Container(
              width: 54,
              height: 54,
              margin: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  address['icon'] as String? ?? '📍',
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            ),
          ),
          // Infos
          Expanded(
            child: GestureDetector(
              onTap: onEdit,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    address['label'] as String? ?? '',
                    style: ClientText.bodyStrong.copyWith(
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    address['address'] as String? ?? '',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((address['details'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Text(
                      address['details'] as String,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.primary.withValues(alpha: 0.70),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Actions
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: onEdit,
                icon: Icon(
                  Icons.edit_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline,
                  color: AppColors.error,
                  size: 20,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Emplacement réservé (Maison/Bureau) — état vide ou rempli ───────────────
class _SlotTile extends StatelessWidget {
  final Map<String, dynamic>? existing;
  final String label;
  final String icon;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  const _SlotTile({
    required this.existing,
    required this.label,
    required this.icon,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final e = existing;
    if (e != null) {
      return _AddressTile(address: e, onEdit: onTap, onDelete: onDelete!);
    }
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.lightFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.lightBorder, width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(icon, style: const TextStyle(fontSize: 22)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: ClientText.bodyStrong.copyWith(
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Non renseignée — appuyez pour ajouter',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.add_circle_outline,
              color: AppColors.primary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Ajouter l'adresse personnalisée ──────────────────────────────────────────
class _AddCustomTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddCustomTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.25),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.add_location_alt_outlined,
              color: AppColors.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Ajouter une adresse personnalisée',
              style: ClientText.button.copyWith(color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Formulaire (bottom sheet) ─────────────────────────────────────────────────
class _AddressFormSheet extends StatefulWidget {
  final Map<String, dynamic>? existing;
  // Si renseigné, le nom est fixé (emplacement réservé "Maison"/"Bureau")
  // et le champ Nom devient non modifiable.
  final String? lockedLabel;
  final String? defaultIcon;
  const _AddressFormSheet({this.existing, this.lockedLabel, this.defaultIcon});
  @override
  State<_AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends State<_AddressFormSheet> {
  final _labelCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();
  String _icon = '📍';
  double? _lat, _lng;
  List<Map<String, dynamic>> _suggestions = [];
  bool _searching = false;
  String? _searchError;
  String? _sessionToken;
  bool _locating = false;
  Timer? _debounce;
  final _dio = Dio();
  late final _placesService = PlacesAutocompleteService(_dio);

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _labelCtrl.text = e['label'] as String? ?? '';
      _addressCtrl.text = e['address'] as String? ?? '';
      _detailsCtrl.text = e['details'] as String? ?? '';
      _icon = e['icon'] as String? ?? '📍';
      _lat = (e['lat'] as num?)?.toDouble();
      _lng = (e['lng'] as num?)?.toDouble();
    } else if (widget.lockedLabel != null) {
      _labelCtrl.text = widget.lockedLabel!;
      _icon = widget.defaultIcon ?? _icon;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _labelCtrl.dispose();
    _addressCtrl.dispose();
    _detailsCtrl.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _labelCtrl.text.trim().isNotEmpty &&
      _addressCtrl.text.trim().isNotEmpty &&
      _lat != null &&
      _lng != null;

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _suggestions = [];
    });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied)
        perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) {
        if (mounted)
          showDemToast(
            context,
            'Autorisez la localisation dans les réglages.',
            isError: true,
          );
        return;
      }
      final pos = await Geolocator.getCurrentPosition();

      // Google Geocoding en premier (couvre bien mieux Dakar que le
      // géocodeur natif) puis le géocodeur natif iOS/Android en secours —
      // jamais de coordonnées brutes affichées à l'utilisateur.
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

      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _addressCtrl.text = (addr != null && addr.isNotEmpty)
            ? addr
            : 'Position sélectionnée';
      });
    } catch (_) {
      if (mounted)
        showDemToast(
          context,
          'Impossible de récupérer la position.',
          isError: true,
        );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _onAddressChanged(String q) {
    setState(() {
      _lat = null;
      _lng = null;
    });
    _debounce?.cancel();
    if (q.trim().length < 3) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = []);
      return;
    }
    _sessionToken ??= PlacesAutocompleteService.newSessionToken();
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      setState(() {
        _searching = true;
        _searchError = null;
      });
      try {
        final preds = await _placesService.autocomplete(
          query: q,
          sessionToken: _sessionToken!,
        );
        if (mounted)
          setState(() {
            _suggestions = preds;
            _searching = false;
          });
      } catch (e) {
        if (mounted)
          setState(() {
            _searching = false;
            _searchError = friendlyError(e);
          });
      }
    });
  }

  void _retryAddressSearch() => _onAddressChanged(_addressCtrl.text);

  Future<void> _selectSuggestion(Map<String, dynamic> place) async {
    FocusScope.of(context).unfocus();
    setState(() => _suggestions = []);
    final placeId = place['place_id'] as String?;
    if (placeId == null) return;
    final token = _sessionToken ?? PlacesAutocompleteService.newSessionToken();
    try {
      final result = await _placesService.details(
        placeId: placeId,
        sessionToken: token,
      );
      if (result != null) {
        final loc = result['geometry']['location'];
        final addr =
            result['formatted_address'] as String? ??
            (place['structured_formatting']?['main_text'] as String? ?? '');
        setState(() {
          _lat = (loc['lat'] as num).toDouble();
          _lng = (loc['lng'] as num).toDouble();
          _addressCtrl.text = addr;
        });
      }
    } catch (_) {
    } finally {
      _sessionToken = null;
    }
  }

  void _save() {
    if (!_canSave) return;
    Navigator.pop(context, {
      'label': _labelCtrl.text.trim(),
      'icon': _icon,
      'address': _addressCtrl.text.trim(),
      'lat': _lat,
      'lng': _lng,
      'details': _detailsCtrl.text.trim().isEmpty
          ? null
          : _detailsCtrl.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final isLocked = widget.lockedLabel != null;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Titre
            Text(
              isLocked
                  ? (isEdit
                        ? 'Modifier "${widget.lockedLabel}"'
                        : 'Ajouter "${widget.lockedLabel}"')
                  : (isEdit
                        ? 'Modifier l\'adresse'
                        : 'Nouvelle adresse personnalisée'),
              style: ClientText.subtitle.copyWith(color: AppColors.textDark),
            ),
            const SizedBox(height: 20),

            // Sélecteur d'icône
            Text(
              'Icône',
              style: ClientText.label.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _kIcons
                  .map(
                    (ic) => GestureDetector(
                      onTap: () => setState(() => _icon = ic),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _icon == ic
                              ? AppColors.primary.withValues(alpha: 0.12)
                              : AppColors.lightFill,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _icon == ic
                                ? AppColors.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(ic, style: const TextStyle(fontSize: 20)),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),

            // Label — verrouillé pour les emplacements réservés Maison/Bureau,
            // sans ça rien n'empêcherait de vider ce que ce slot est censé
            // représenter.
            if (isLocked)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: AppColors.lightFill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: AppColors.textMuted.withValues(alpha: 0.70),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      widget.lockedLabel!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            else
              _Field(
                ctrl: _labelCtrl,
                label: 'Nom (ex: Chez maman, Salon…)',
                icon: Icons.label_outline,
                onChanged: (_) => setState(() {}),
              ),
            const SizedBox(height: 12),

            // Adresse avec autocomplete
            _Field(
              ctrl: _addressCtrl,
              label: 'Adresse',
              icon: Icons.place_outlined,
              onChanged: _onAddressChanged,
              suffix: _lat != null
                  ? Icon(
                      Icons.check_circle,
                      color: Colors.green.shade600,
                      size: 18,
                    )
                  : _searching
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  : _addressCtrl.text.trim().isNotEmpty
                  ? Icon(
                      Icons.error_outline,
                      color: Colors.orange.shade700,
                      size: 18,
                    )
                  : null,
            ),
            // Adresse tapée mais pas encore confirmée (coordonnées GPS
            // manquantes) — ex. après modification du texte d'une adresse
            // existante. Sans ce message, "Enregistrer" reste grisé sans
            // explication visible.
            if (_addressCtrl.text.trim().isNotEmpty &&
                _lat == null &&
                !_searching) ...[
              const SizedBox(height: 6),
              Text(
                'Sélectionnez une adresse dans la liste ou utilisez votre position actuelle.',
                style: TextStyle(fontSize: 11.5, color: Colors.orange.shade800),
              ),
            ],
            const SizedBox(height: 8),
            // Bouton position actuelle
            GestureDetector(
              onTap: _locating ? null : _useCurrentLocation,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    _locating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : Icon(
                            Icons.my_location,
                            color: AppColors.primary,
                            size: 16,
                          ),
                    const SizedBox(width: 8),
                    Text(
                      _locating
                          ? 'Localisation en cours…'
                          : 'Utiliser ma position actuelle',
                      style: ClientText.body.copyWith(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ),
            // Dropdown suggestions
            if (_suggestions.isNotEmpty ||
                _searching ||
                _searchError != null) ...[
              const SizedBox(height: 4),
              PlaceSuggestionsList(
                suggestions: _suggestions,
                loading: _searching,
                error: _searchError,
                onRetry: _retryAddressSearch,
                onSelect: _selectSuggestion,
                colors: _placeSuggestionsColors,
                maxHeight: 200,
              ),
            ],
            const SizedBox(height: 12),

            // Détails
            _Field(
              ctrl: _detailsCtrl,
              label: 'Instructions (optionnel)',
              icon: Icons.info_outline,
            ),
            const SizedBox(height: 24),

            // Bouton
            PrimaryButton(
              label: isEdit ? 'Enregistrer' : 'Ajouter l\'adresse',
              color: AppColors.primary,
              disabledColor: AppColors.lightBorder,
              onTap: _canSave ? _save : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;
  const _Field({
    required this.ctrl,
    required this.label,
    required this.icon,
    this.onChanged,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    onChanged: onChanged,
    style: const TextStyle(fontSize: 14, color: AppColors.textDark),
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(
        icon,
        size: 18,
        color: AppColors.primary.withValues(alpha: 0.70),
      ),
      suffixIcon: suffix != null
          ? Padding(padding: const EdgeInsets.only(right: 12), child: suffix)
          : null,
      suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      filled: true,
      fillColor: AppColors.lightFill,
      labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
  );
}
