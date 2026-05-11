import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import 'data/favorite_addresses_repository.dart';

const _kIcons = ['📍', '🏠', '💼', '❤️', '🛒', '🏫', '🏥', '🕌', '⭐'];
const _kMax   = 6;

class FavoriteAddressesScreen extends StatefulWidget {
  const FavoriteAddressesScreen({super.key});
  @override
  State<FavoriteAddressesScreen> createState() => _FavoriteAddressesScreenState();
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
      if (mounted) setState(() { _addresses = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([Map<String, dynamic>? existing]) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddressFormSheet(existing: existing),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> addr) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Supprimer "${addr['label']}" ?',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.delete(addr['id'] as String);
      if (mounted) setState(() => _addresses.removeWhere((a) => a['id'] == addr['id']));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      body: Column(children: [
        // ── Header ──────────────────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(children: [
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                ),
                const Spacer(),
                const Text('Adresses favorites',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                const SizedBox(width: 48),
              ]),
            ),
          ),
        ),

        // ── Corps ───────────────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _addresses.isEmpty
                  ? _EmptyState(onAdd: () => _openForm())
                  : RefreshIndicator(
                      onRefresh: _fetch,
                      color: AppColors.primary,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
                        itemCount: _addresses.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _AddressTile(
                          address: _addresses[i],
                          onEdit: () => _openForm(_addresses[i]),
                          onDelete: () => _confirmDelete(_addresses[i]),
                        ),
                      ),
                    ),
        ),
      ]),

      floatingActionButton: _addresses.length < _kMax
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Ajouter', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
    );
  }
}

// ── Tile adresse ──────────────────────────────────────────────────────────────
class _AddressTile extends StatelessWidget {
  final Map<String, dynamic> address;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _AddressTile({required this.address, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        // Icône
        Container(
          width: 54, height: 54,
          margin: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Center(child: Text(address['icon'] as String? ?? '📍', style: const TextStyle(fontSize: 22))),
        ),
        // Infos
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(address['label'] as String? ?? '',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
            const SizedBox(height: 2),
            Text(address['address'] as String? ?? '',
                style: const TextStyle(fontSize: 12, color: Color(0xFF7B8CA0)),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if ((address['details'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 2),
              Text(address['details'] as String,
                  style: TextStyle(fontSize: 11, color: AppColors.primary.withValues(alpha: 0.70)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ]),
        ),
        // Actions
        Column(mainAxisSize: MainAxisSize.min, children: [
          IconButton(onPressed: onEdit,   icon: Icon(Icons.edit_outlined,  color: AppColors.primary, size: 20)),
          IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 20)),
        ]),
      ]),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('📍', style: const TextStyle(fontSize: 56)),
      const SizedBox(height: 16),
      const Text('Aucune adresse favorite',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
      const SizedBox(height: 6),
      const Text('Enregistrez vos adresses fréquentes\npour commander plus vite.',
          style: TextStyle(fontSize: 13, color: Color(0xFF7B8CA0)), textAlign: TextAlign.center),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Ajouter une adresse'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
      ),
    ]),
  );
}

// ── Formulaire (bottom sheet) ─────────────────────────────────────────────────
class _AddressFormSheet extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _AddressFormSheet({this.existing});
  @override
  State<_AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends State<_AddressFormSheet> {
  final _labelCtrl   = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();
  String _icon = '📍';
  double? _lat, _lng;
  List<Map<String, dynamic>> _suggestions = [];
  bool _searching = false;
  bool _locating  = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _labelCtrl.text   = e['label']   as String? ?? '';
      _addressCtrl.text = e['address'] as String? ?? '';
      _detailsCtrl.text = e['details'] as String? ?? '';
      _icon = e['icon'] as String? ?? '📍';
      _lat  = (e['lat'] as num?)?.toDouble();
      _lng  = (e['lng'] as num?)?.toDouble();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _labelCtrl.dispose(); _addressCtrl.dispose(); _detailsCtrl.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _labelCtrl.text.trim().isNotEmpty &&
      _addressCtrl.text.trim().isNotEmpty &&
      _lat != null && _lng != null;

  Future<void> _useCurrentLocation() async {
    setState(() { _locating = true; _suggestions = []; });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Autorisez la localisation dans les réglages.')));
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final marks = await geo.placemarkFromCoordinates(pos.latitude, pos.longitude)
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      final p = marks.isNotEmpty ? marks.first : null;
      final street = p?.street ?? p?.name ?? '';
      final local  = p?.subLocality ?? p?.locality ?? '';
      final addr   = street.isNotEmpty ? '$street, $local' : local.isNotEmpty
          ? local : '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _addressCtrl.text = addr;
      });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de récupérer la position.')));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _onAddressChanged(String q) {
    setState(() { _lat = null; _lng = null; });
    _debounce?.cancel();
    if (q.trim().length < 3) { if (_suggestions.isNotEmpty) setState(() => _suggestions = []); return; }
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      try {
        final res = await Dio().get(
          'https://maps.googleapis.com/maps/api/place/autocomplete/json',
          queryParameters: {
            'input': q, 'location': '14.6937,-17.4441', 'radius': '60000',
            'components': 'country:sn', 'language': 'fr', 'key': AppConfig.mapsApiKey,
          },
        );
        if (mounted && res.statusCode == 200) {
          final preds = res.data['status'] == 'OK'
              ? List<Map<String, dynamic>>.from(res.data['predictions'])
              : <Map<String, dynamic>>[];
          setState(() { _suggestions = preds; _searching = false; });
        }
      } catch (_) { if (mounted) setState(() => _searching = false); }
    });
  }

  Future<void> _selectSuggestion(Map<String, dynamic> place) async {
    FocusScope.of(context).unfocus();
    setState(() => _suggestions = []);
    try {
      final res = await Dio().get(
        'https://maps.googleapis.com/maps/api/place/details/json',
        queryParameters: {
          'place_id': place['place_id'], 'fields': 'geometry,formatted_address',
          'language': 'fr', 'key': AppConfig.mapsApiKey,
        },
      );
      if (res.statusCode == 200 && res.data['status'] == 'OK') {
        final loc  = res.data['result']['geometry']['location'];
        final addr = res.data['result']['formatted_address'] as String?
            ?? (place['structured_formatting']?['main_text'] as String? ?? '');
        setState(() {
          _lat = (loc['lat'] as num).toDouble();
          _lng = (loc['lng'] as num).toDouble();
          _addressCtrl.text = addr;
        });
      }
    } catch (_) {}
  }

  void _save() {
    if (!_canSave) return;
    Navigator.pop(context, {
      'label':   _labelCtrl.text.trim(),
      'icon':    _icon,
      'address': _addressCtrl.text.trim(),
      'lat':     _lat,
      'lng':     _lng,
      'details': _detailsCtrl.text.trim().isEmpty ? null : _detailsCtrl.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Handle
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),

          // Titre
          Text(isEdit ? 'Modifier l\'adresse' : 'Nouvelle adresse favorite',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 20),

          // Sélecteur d'icône
          const Text('Icône', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF7B8CA0))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: _kIcons.map((ic) => GestureDetector(
            onTap: () => setState(() => _icon = ic),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: _icon == ic ? AppColors.primary.withValues(alpha: 0.12) : const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _icon == ic ? AppColors.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Center(child: Text(ic, style: const TextStyle(fontSize: 20))),
            ),
          )).toList()),
          const SizedBox(height: 16),

          // Label
          _Field(ctrl: _labelCtrl, label: 'Nom (ex: Maison, Bureau…)', icon: Icons.label_outline,
              onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),

          // Adresse avec autocomplete
          _Field(ctrl: _addressCtrl, label: 'Adresse', icon: Icons.place_outlined,
              onChanged: _onAddressChanged,
              suffix: _lat != null
                  ? Icon(Icons.check_circle, color: Colors.green.shade600, size: 18)
                  : (_searching ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)) : null)),
          const SizedBox(height: 8),
          // Bouton position actuelle
          GestureDetector(
            onTap: _locating ? null : _useCurrentLocation,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
              ),
              child: Row(children: [
                _locating
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                    : Icon(Icons.my_location, color: AppColors.primary, size: 16),
                const SizedBox(width: 8),
                Text(
                  _locating ? 'Localisation en cours…' : 'Utiliser ma position actuelle',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ]),
            ),
          ),
          // Dropdown suggestions
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEEF0F5)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12)],
              ),
              child: ListView.separated(
                padding: EdgeInsets.zero, shrinkWrap: true,
                itemCount: _suggestions.length,
                separatorBuilder: (_, _) => const Divider(height: 1, color: Color(0xFFEEF0F5)),
                itemBuilder: (_, i) {
                  final p = _suggestions[i];
                  final main = (p['structured_formatting']?['main_text'] as String?) ?? '';
                  final sec  = (p['structured_formatting']?['secondary_text'] as String?) ?? '';
                  return InkWell(
                    onTap: () => _selectSuggestion(p),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      child: Row(children: [
                        Icon(Icons.place_outlined, size: 16, color: AppColors.primary.withValues(alpha: 0.70)),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(main, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          if (sec.isNotEmpty) Text(sec, style: const TextStyle(fontSize: 11, color: Color(0xFF7B8CA0))),
                        ])),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Détails
          _Field(ctrl: _detailsCtrl, label: 'Instructions (optionnel)', icon: Icons.info_outline),
          const SizedBox(height: 24),

          // Bouton
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canSave ? _save : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: const Color(0xFFEEF0F5),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: Text(isEdit ? 'Enregistrer' : 'Ajouter l\'adresse',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ]),
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
  const _Field({required this.ctrl, required this.label, required this.icon, this.onChanged, this.suffix});

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    onChanged: onChanged,
    style: const TextStyle(fontSize: 14, color: Color(0xFF1A1A2E)),
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 18, color: AppColors.primary.withValues(alpha: 0.70)),
      suffixIcon: suffix != null ? Padding(padding: const EdgeInsets.only(right: 12), child: suffix) : null,
      suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      filled: true, fillColor: const Color(0xFFF1F5F9),
      labelStyle: const TextStyle(color: Color(0xFF7B8CA0), fontSize: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
  );
}
