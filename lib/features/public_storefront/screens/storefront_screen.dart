import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/services/places_autocomplete_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';
import '../../../core/utils/dem_toast.dart';
import '../../../core/utils/price_format.dart';
import '../../../core/utils/senegal_phone.dart';
import '../../../shared/widgets/place_suggestions_list.dart';
import '../../../shared/widgets/staggered_entrance.dart';
import '../../home_driver/navigation/navigation_service.dart';

const List<(String, String, String)> _paymentMethods = [
  ('CASH', '💵', 'Espèces'),
  ('WAVE', '🌊', 'Wave'),
  ('ORANGE_MONEY', '🟠', 'Orange Money'),
  ('FREE_MONEY', '🔵', 'Free Money'),
];

/// Boutique publique d'un DEM Pro, ouverte via le lien de commande
/// (dem.sn/commander/:id sur le web, dem://commander/:id dans l'app) — même
/// fonctionnalité que OrderRequest.jsx côté web, en natif. Aucun compte
/// requis : utilise son propre Dio (jamais ApiClient.dio, dont
/// l'intercepteur déconnecterait un visiteur non authentifié sur un 401),
/// même précaution que guest_tracking_screen.dart.
class StorefrontScreen extends StatefulWidget {
  final String merchantId;
  const StorefrontScreen({super.key, required this.merchantId});

  @override
  State<StorefrontScreen> createState() => _StorefrontScreenState();
}

class _StorefrontScreenState extends State<StorefrontScreen> {
  final _dio = Dio(
    BaseOptions(
      baseUrl: apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );
  late final _places = PlacesAutocompleteService(_dio);

  Map<String, dynamic>? _merchant;
  bool _loading = true;
  bool _notFound = false;

  List<Map<String, dynamic>> _products = [];
  final Map<String, int> _cart = {};

  String _deliveryAddress = '';
  double? _deliveryLat, _deliveryLng;
  bool _loadingGps = false;

  String _paymentMethod = 'CASH';
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _submitting = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _landmarkCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _dio.get('/public/dem-pro/${widget.merchantId}');
      final productsRes = await _dio.get(
        '/public/dem-pro/${widget.merchantId}/products',
      );
      if (!mounted) return;
      setState(() {
        _merchant = res.data as Map<String, dynamic>;
        _products = (productsRes.data as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _notFound = true;
        });
    }
  }

  // ── Panier ─────────────────────────────────────────────────────────────
  void _changeQty(Map<String, dynamic> product, int qty) {
    final id = product['id'] as String;
    final stock = (product['quantity'] as num?)?.toInt();
    final clamped = stock != null ? qty.clamp(0, stock) : (qty < 0 ? 0 : qty);
    setState(() {
      if (clamped <= 0) {
        _cart.remove(id);
      } else {
        _cart[id] = clamped;
      }
    });
  }

  List<Map<String, dynamic>> get _cartItems => _cart.entries
      .map((e) {
        final product = _products.firstWhere(
          (p) => p['id'] == e.key,
          orElse: () => {},
        );
        if (product.isEmpty) return null;
        return {
          'productId': e.key,
          'name': product['name'],
          'price': (product['defaultPrice'] as num?) ?? 0,
          'quantity': e.value,
        };
      })
      .whereType<Map<String, dynamic>>()
      .toList();

  num get _cartTotal => _cartItems.fold<num>(
    0,
    (sum, item) => sum + (item['price'] as num) * (item['quantity'] as int),
  );

  // ── Adresse ────────────────────────────────────────────────────────────
  Future<void> _useGps() async {
    setState(() => _loadingGps = true);
    try {
      final pos = await NavigationService.requestAndGetPosition();
      if (pos == null) {
        if (mounted) {
          showDemToast(
            context,
            'Activez la localisation pour continuer',
            isError: true,
          );
        }
        return;
      }
      final address = await _places.reverseGeocode(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _deliveryLat = pos.latitude;
        _deliveryLng = pos.longitude;
        _deliveryAddress = address ?? 'Position GPS actuelle';
      });
    } catch (_) {
      if (mounted) showDemToast(context, 'GPS indisponible', isError: true);
    } finally {
      if (mounted) setState(() => _loadingGps = false);
    }
  }

  Future<void> _searchAddress() async {
    final result =
        await showModalBottomSheet<({String address, double lat, double lng})>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _AddressSearchSheet(places: _places),
        );
    if (result != null && mounted) {
      setState(() {
        _deliveryAddress = result.address;
        _deliveryLat = result.lat;
        _deliveryLng = result.lng;
      });
    }
  }

  // ── Soumission ─────────────────────────────────────────────────────────
  bool get _canSubmit =>
      _deliveryAddress.trim().length >= 4 &&
      _cartItems.isNotEmpty &&
      !_submitting;

  Future<void> _submit() async {
    if (!_canSubmit) {
      showDemToast(
        context,
        _cartItems.isEmpty
            ? 'Choisissez au moins un produit'
            : 'Renseignez l\'adresse de livraison',
        isError: true,
      );
      return;
    }
    final phone = _phoneCtrl.text.trim();
    if (phone.isNotEmpty && !isValidSenegalMobile(phone)) {
      showDemToast(
        context,
        'Numéro mobile invalide (7X XXX XX XX)',
        isError: true,
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await _dio.post(
        '/public/dem-pro/${widget.merchantId}/order-requests',
        data: {
          if (_nameCtrl.text.trim().isNotEmpty)
            'customerName': _nameCtrl.text.trim(),
          if (phone.isNotEmpty) 'customerPhone': phone,
          'deliveryAddress': _deliveryAddress.trim(),
          if (_deliveryLat != null) 'deliveryLatitude': _deliveryLat,
          if (_deliveryLng != null) 'deliveryLongitude': _deliveryLng,
          if (_landmarkCtrl.text.trim().isNotEmpty)
            'landmark': _landmarkCtrl.text.trim(),
          if (_notesCtrl.text.trim().isNotEmpty)
            'notes': _notesCtrl.text.trim(),
          'items': _cartItems
              .map(
                (i) => {'productId': i['productId'], 'quantity': i['quantity']},
              )
              .toList(),
          'customerPaymentMethod': _paymentMethod,
        },
      );
      if (mounted) setState(() => _submitted = true);
    } on DioException catch (e) {
      if (mounted) {
        showDemToast(
          context,
          e.response?.data?['message'] as String? ??
              'Impossible d\'envoyer votre demande.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBg,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : _notFound
            ? _buildNotFound()
            : _submitted
            ? _buildSubmitted()
            : _buildForm(),
      ),
    );
  }

  Widget _buildNotFound() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.link_off_rounded,
            color: AppColors.textMuted,
            size: 44,
          ),
          const SizedBox(height: 16),
          Text(
            'Ce lien de commande n\'est plus disponible',
            style: ClientText.title.copyWith(
              color: AppColors.textDark,
              fontSize: 17,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Il a peut-être expiré ou le compte n\'est plus actif.',
            style: ClientText.body.copyWith(color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  Widget _buildSubmitted() {
    final businessName =
        _merchant?['businessName'] as String? ?? 'Ce commerçant';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.successLight.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: AppColors.successLight,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Demande envoyée !',
              style: ClientText.title.copyWith(
                color: AppColors.textDark,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$businessName va confirmer votre commande. Un livreur DEM viendra récupérer et vous livrer votre colis.',
              style: ClientText.body.copyWith(
                color: AppColors.textMuted,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    final businessName =
        _merchant?['businessName'] as String? ?? 'Commerçant DEM';
    return Column(
      children: [
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Commander chez',
                style: ClientText.label.copyWith(
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                businessName,
                style: ClientText.headline.copyWith(
                  color: Colors.white,
                  fontSize: 22,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              StaggeredEntrance(index: 0, child: _buildCatalogue()),
              if (_cartItems.isNotEmpty) ...[
                const SizedBox(height: 16),
                StaggeredEntrance(index: 1, child: _buildCartSummary()),
              ],
              const SizedBox(height: 16),
              StaggeredEntrance(index: 2, child: _buildAddressSection()),
              const SizedBox(height: 16),
              StaggeredEntrance(index: 3, child: _buildPaymentSection()),
              const SizedBox(height: 16),
              StaggeredEntrance(index: 4, child: _buildContactSection()),
              const SizedBox(height: 20),
              _buildSubmitButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCatalogue() {
    if (_products.isEmpty) {
      return _card(
        child: Text(
          'Ce commerçant n\'a pas encore de produits dans son catalogue.',
          style: ClientText.body.copyWith(color: AppColors.textMuted),
        ),
      );
    }
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final p in _products) {
      final cat = (p['category'] as String?)?.trim();
      final key = (cat == null || cat.isEmpty) ? 'Autres produits' : cat;
      grouped.putIfAbsent(key, () => []).add(p);
    }
    final keys = grouped.keys.toList()
      ..sort((a, b) {
        if (a == 'Autres produits') return 1;
        if (b == 'Autres produits') return -1;
        return a.compareTo(b);
      });

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.shopping_bag_outlined, 'Catalogue'),
          const SizedBox(height: 10),
          for (final key in keys) ...[
            if (keys.length > 1) ...[
              Text(
                key.toUpperCase(),
                style: ClientText.micro.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
            ],
            for (final p in grouped[key]!) _buildProductRow(p),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildProductRow(Map<String, dynamic> product) {
    final id = product['id'] as String;
    final name = product['name'] as String? ?? '';
    final price = product['defaultPrice'] as num?;
    final stock = (product['quantity'] as num?)?.toInt();
    final qty = _cart[id] ?? 0;
    final atMax = stock != null && qty >= stock;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: ClientText.bodyStrong.copyWith(
                    color: AppColors.textDark,
                  ),
                ),
                Text(
                  price != null ? formatFcfa(price) : 'Prix sur demande',
                  style: ClientText.label.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          _qtyButton(Icons.remove, qty > 0, () => _changeQty(product, qty - 1)),
          SizedBox(
            width: 28,
            child: Text(
              '$qty',
              textAlign: TextAlign.center,
              style: ClientText.bodyStrong.copyWith(color: AppColors.textDark),
            ),
          ),
          _qtyButton(Icons.add, !atMax, () => _changeQty(product, qty + 1)),
        ],
      ),
    );
  }

  Widget _qtyButton(IconData icon, bool enabled, VoidCallback onTap) =>
      GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: enabled
                ? AppColors.primary.withValues(alpha: 0.1)
                : AppColors.lightFill,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 16,
            color: enabled ? AppColors.primary : AppColors.textMuted,
          ),
        ),
      );

  Widget _buildCartSummary() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(Icons.shopping_basket_outlined, 'Votre panier'),
        const SizedBox(height: 10),
        for (final item in _cartItems)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${item['name']} × ${item['quantity']}',
                    style: ClientText.body.copyWith(color: AppColors.textDark),
                  ),
                ),
                Text(
                  formatFcfa(
                    (item['price'] as num) * (item['quantity'] as int),
                  ),
                  style: ClientText.label.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        const Divider(height: 20),
        Row(
          children: [
            Text(
              'Total',
              style: ClientText.bodyStrong.copyWith(color: AppColors.textDark),
            ),
            const Spacer(),
            Text(
              formatFcfa(_cartTotal),
              style: ClientText.title.copyWith(
                color: AppColors.primary,
                fontSize: 17,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildAddressSection() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(Icons.location_on_outlined, 'Adresse de livraison'),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _loadingGps ? null : _useGps,
            icon: _loadingGps
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded, size: 16),
            label: Text(
              _loadingGps ? 'Localisation…' : 'Utiliser ma position actuelle',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _searchAddress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.lightFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.lightBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: AppColors.textMuted, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _deliveryAddress.isEmpty
                        ? 'Rechercher une adresse…'
                        : _deliveryAddress,
                    style: ClientText.body.copyWith(
                      color: _deliveryAddress.isEmpty
                          ? AppColors.textMuted
                          : AppColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _FieldLabel('Repère (optionnel)'),
        const SizedBox(height: 4),
        _textField(_landmarkCtrl, 'Ex: face à la pharmacie, portail bleu…'),
        const SizedBox(height: 10),
        _FieldLabel('Instructions pour le livreur (optionnel)'),
        const SizedBox(height: 4),
        _textField(_notesCtrl, 'Ex: m\'appeler à l\'arrivée…', maxLines: 3),
      ],
    ),
  );

  Widget _buildPaymentSection() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          Icons.payments_outlined,
          'Mode de paiement à la livraison',
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in _paymentMethods) _paymentChip(m.$1, m.$2, m.$3),
          ],
        ),
      ],
    ),
  );

  Widget _paymentChip(String value, String emoji, String label) {
    final active = _paymentMethod == value;
    return GestureDetector(
      onTap: () => setState(() => _paymentMethod = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.lightFill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.lightBorder,
          ),
        ),
        child: Text(
          '$emoji  $label',
          style: ClientText.body.copyWith(
            color: active ? AppColors.primary : AppColors.textDark,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildContactSection() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(Icons.person_outline, 'Vos coordonnées (optionnel)'),
        const SizedBox(height: 10),
        _FieldLabel('Votre nom'),
        const SizedBox(height: 4),
        _textField(_nameCtrl, 'Prénom Nom'),
        const SizedBox(height: 10),
        _FieldLabel('Votre téléphone'),
        const SizedBox(height: 4),
        _textField(
          _phoneCtrl,
          '7X XXX XX XX',
          keyboardType: TextInputType.phone,
        ),
      ],
    ),
  );

  Widget _buildSubmitButton() => SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
      onPressed: _submitting ? null : _submit,
      style: ElevatedButton.styleFrom(
        backgroundColor: _canSubmit ? AppColors.primary : AppColors.lightFill,
        foregroundColor: _canSubmit ? Colors.white : AppColors.textMuted,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: _submitting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              _cartTotal > 0
                  ? 'Envoyer ma demande — ${formatFcfa(_cartTotal)}'
                  : 'Envoyer ma demande',
              style: ClientText.button,
            ),
    ),
  );

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.lightBorder),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.06),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: child,
  );

  Widget _sectionTitle(IconData icon, String label) => Row(
    children: [
      Icon(icon, color: AppColors.primary, size: 17),
      const SizedBox(width: 8),
      Text(
        label,
        style: ClientText.bodyStrong.copyWith(color: AppColors.textDark),
      ),
    ],
  );

  Widget _textField(
    TextEditingController ctrl,
    String hint, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) => TextField(
    controller: ctrl,
    maxLines: maxLines,
    keyboardType: keyboardType,
    style: ClientText.body.copyWith(color: AppColors.textDark),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: ClientText.body.copyWith(color: AppColors.textMuted),
      filled: true,
      fillColor: AppColors.lightFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.lightBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.lightBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: ClientText.label.copyWith(color: AppColors.textMuted));
}

// ── Feuille de recherche d'adresse ──────────────────────────────────────────
class _AddressSearchSheet extends StatefulWidget {
  final PlacesAutocompleteService places;
  const _AddressSearchSheet({required this.places});

  @override
  State<_AddressSearchSheet> createState() => _AddressSearchSheetState();
}

class _AddressSearchSheetState extends State<_AddressSearchSheet> {
  final _searchCtrl = TextEditingController();
  final _sessionToken = PlacesAutocompleteService.newSessionToken();
  Timer? _debounce;
  List<Map<String, dynamic>> _suggestions = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() {
        _loading = true;
        _error = null;
      });
      try {
        final results = await widget.places.autocomplete(
          query: query,
          sessionToken: _sessionToken,
        );
        if (mounted)
          setState(() {
            _suggestions = results;
            _loading = false;
          });
      } catch (_) {
        if (mounted)
          setState(() {
            _error = 'Recherche indisponible';
            _loading = false;
          });
      }
    });
  }

  Future<void> _select(Map<String, dynamic> place) async {
    try {
      final details = await widget.places.details(
        placeId: place['place_id'] as String,
        sessionToken: _sessionToken,
      );
      final loc = details?['geometry']?['location'] as Map<String, dynamic>?;
      final lat = (loc?['lat'] as num?)?.toDouble();
      final lng = (loc?['lng'] as num?)?.toDouble();
      if (lat != null && lng != null && mounted) {
        Navigator.pop(context, (
          address:
              details?['formatted_address'] as String? ??
              place['description'] as String? ??
              '',
          lat: lat,
          lng: lng,
        ));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      20,
      16,
      20,
      MediaQuery.of(context).viewInsets.bottom + 20,
    ),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.lightBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        TextField(
          controller: _searchCtrl,
          autofocus: true,
          onChanged: _onChanged,
          style: ClientText.body.copyWith(color: AppColors.textDark),
          decoration: InputDecoration(
            hintText: 'Quartier, rue, numéro…',
            prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.lightFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        PlaceSuggestionsList(
          suggestions: _suggestions,
          loading: _loading,
          error: _error,
          onSelect: _select,
          colors: const PlaceSuggestionsColors(
            background: Colors.white,
            border: AppColors.lightBorder,
            divider: AppColors.lightBorder,
            iconBg: AppColors.lightFill,
            icon: AppColors.primary,
            mainText: AppColors.textDark,
            secondaryText: AppColors.textMuted,
            accent: AppColors.primary,
            shadow: Color(0x14000000),
          ),
        ),
      ],
    ),
  );
}
