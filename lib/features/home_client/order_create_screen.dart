import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../deliveries/data/orders_repository.dart';

class OrderCreateScreen extends StatefulWidget {
  /// 'RIDE' = transport humain (Thiak Thiak) | 'DELIVERY' = livraison colis
  final String orderType;
  const OrderCreateScreen({super.key, this.orderType = 'DELIVERY'});

  @override
  State<OrderCreateScreen> createState() => _OrderCreateScreenState();
}

class _OrderCreateScreenState extends State<OrderCreateScreen> {
  final _repo = OrdersRepository();

  // ── Form controllers ──────────────────────────────────────────────────────
  final _pickupAddressCtrl   = TextEditingController();
  final _deliveryAddressCtrl = TextEditingController();
  final _deliveryLatCtrl     = TextEditingController();
  final _deliveryLngCtrl     = TextEditingController();
  final _descriptionCtrl     = TextEditingController();

  // ── State ─────────────────────────────────────────────────────────────────
  double? _pickupLat;
  double? _pickupLng;
  double  _surgeMultiplier = 1.0;
  double? _estimatedPrice;
  bool    _loadingGps    = false;
  bool    _loadingSurge  = false;
  bool    _submitting    = false;
  Timer?  _surgeDebounce;

  static const double _baseFare    = 500;
  static const double _pricePerKm  = 200;

  @override
  void dispose() {
    _surgeDebounce?.cancel();
    _pickupAddressCtrl.dispose();
    _deliveryAddressCtrl.dispose();
    _deliveryLatCtrl.dispose();
    _deliveryLngCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  // ── GPS pickup ────────────────────────────────────────────────────────────
  Future<void> _fetchGps() async {
    setState(() => _loadingGps = true);
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _pickupLat = pos.latitude;
        _pickupLng = pos.longitude;
        _pickupAddressCtrl.text = 'Ma position (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})';
      });
      _updateEstimate();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d\'obtenir la position GPS')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  // ── Calcul prix + surge (debounce 800ms) ──────────────────────────────────
  void _updateEstimate() {
    _surgeDebounce?.cancel();
    _surgeDebounce = Timer(const Duration(milliseconds: 800), _computeEstimate);
  }

  Future<void> _computeEstimate() async {
    final dLat = double.tryParse(_deliveryLatCtrl.text);
    final dLng = double.tryParse(_deliveryLngCtrl.text);
    if (_pickupLat == null || dLat == null || dLng == null) return;

    setState(() => _loadingSurge = true);

    final surge = await _repo.getSurgeMultiplier(_pickupLat!, _pickupLng!);
    final dist  = _haversineKm(_pickupLat!, _pickupLng!, dLat, dLng);
    final price = (_baseFare + dist * _pricePerKm) * surge;

    if (mounted) {
      setState(() {
        _surgeMultiplier = surge;
        _estimatedPrice  = price.roundToDouble();
        _loadingSurge    = false;
      });
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
    final dLat = double.tryParse(_deliveryLatCtrl.text);
    final dLng = double.tryParse(_deliveryLngCtrl.text);

    if (_pickupLat == null || _pickupLng == null) {
      _showError('Activez le GPS pour le point de départ.');
      return;
    }
    if (dLat == null || dLng == null) {
      _showError('Entrez les coordonnées de destination.');
      return;
    }
    if (_deliveryAddressCtrl.text.trim().isEmpty) {
      _showError('Entrez l\'adresse de destination.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final order = await _repo.createOrder({
        'orderType':         widget.orderType,
        'pickupAddress':     _pickupAddressCtrl.text.trim(),
        'pickupLatitude':    _pickupLat,
        'pickupLongitude':   _pickupLng,
        'deliveryAddress':   _deliveryAddressCtrl.text.trim(),
        'deliveryLatitude':  dLat,
        'deliveryLongitude': dLng,
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.orderType == 'RIDE' ? 'Réserver un transport' : 'Nouvelle livraison'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewPadding.bottom + 24),
        children: [
          // ── Départ GPS ──
          _SectionLabel(label: widget.orderType == 'RIDE' ? 'Où êtes-vous ?' : 'Point de départ'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _pickupAddressCtrl,
                readOnly: true,
                decoration: InputDecoration(
                  hintText: 'Appuyez sur GPS →',
                  prefixIcon: const Icon(Icons.my_location, color: AppColors.primary),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _GpsButton(loading: _loadingGps, onTap: _fetchGps),
          ]),

          const SizedBox(height: 20),

          // ── Destination ──
          _SectionLabel(label: 'Destination'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _deliveryAddressCtrl,
            decoration: const InputDecoration(
              hintText: 'Adresse de livraison',
              prefixIcon: Icon(Icons.location_on, color: AppColors.error),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _deliveryLatCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(hintText: 'Latitude'),
                onChanged: (_) => _updateEstimate(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _deliveryLngCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(hintText: 'Longitude'),
                onChanged: (_) => _updateEstimate(),
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // ── Description (livraison uniquement) ──
          if (widget.orderType == 'DELIVERY') ...[
            _SectionLabel(label: 'Description (optionnel)'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descriptionCtrl,
              decoration: const InputDecoration(hintText: 'Ex: médicaments, documents...'),
            ),
            const SizedBox(height: 28),
          ] else
            const SizedBox(height: 28),

          // ── Estimation prix ──
          _PriceEstimate(
            price: _estimatedPrice,
            surgeMultiplier: _surgeMultiplier,
            loading: _loadingSurge,
          ),

          const SizedBox(height: 24),

          // ── Bouton commander ──
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(height: 22, width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background))
                : Text(widget.orderType == 'RIDE' ? 'Réserver' : 'Commander'),
          ),
        ],
      ),
    );
  }
}

// ── Widgets locaux ─────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
  );
}

class _GpsButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _GpsButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: loading ? null : onTap,
    child: Container(
      width: 50, height: 50,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: loading
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background),
            )
          : const Icon(Icons.gps_fixed, color: AppColors.background),
    ),
  );
}

class _PriceEstimate extends StatelessWidget {
  final double? price;
  final double surgeMultiplier;
  final bool loading;
  const _PriceEstimate({required this.price, required this.surgeMultiplier, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (price == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14)),
        child: const Text('Entrez les coordonnées pour estimer le prix',
          style: TextStyle(color: AppColors.textSecondary), textAlign: TextAlign.center),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: surgeMultiplier > 1.0
            ? Border.all(color: const Color(0xFFFF9800), width: 1.5)
            : null,
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Prix estimé', style: TextStyle(color: AppColors.textSecondary)),
          Text('${price!.toInt()} FCFA',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
        ]),
        if (surgeMultiplier > 1.0) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.local_fire_department, color: Color(0xFFFF9800), size: 16),
              const SizedBox(width: 6),
              Text('Forte demande — ×${surgeMultiplier.toStringAsFixed(1)}',
                style: const TextStyle(color: Color(0xFFFF9800), fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
          ),
        ],
      ]),
    );
  }
}
