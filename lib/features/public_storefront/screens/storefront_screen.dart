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
import '../../../shared/widgets/product_thumb.dart';
import '../../../shared/widgets/staggered_entrance.dart';
import '../../home_driver/navigation/navigation_service.dart';

// Pas de logos de marque (Wave/Orange Money/Free Money) — un badge de
// couleur + le nom suffit à identifier le moyen de paiement, plus sobre
// qu'un emoji et sans dépendre d'assets de marque.
const List<(String, Color, String)> _paymentMethods = [
  ('CASH', Color(0xFF00E08C), 'Espèces'),
  ('WAVE', Color(0xFF1DC8CE), 'Wave'),
  ('ORANGE_MONEY', Color(0xFFFF7A00), 'Orange Money'),
  ('FREE_MONEY', Color(0xFF7B61FF), 'Free Money'),
];

const List<String> _stepLabels = ['Catalogue', 'Adresse', 'Paiement', 'Résumé'];

/// Boutique publique d'un DEM Pro, ouverte via le lien de commande
/// (dem.sn/commander/:id sur le web, dem://commander/:id dans l'app) — même
/// fonctionnalité que OrderRequest.jsx côté web, en natif. Aucun compte
/// requis : utilise son propre Dio (jamais ApiClient.dio, dont
/// l'intercepteur déconnecterait un visiteur non authentifié sur un 401),
/// même précaution que guest_tracking_screen.dart.
///
/// Parcours en 4 étapes (Catalogue → Adresse → Paiement → Résumé) plutôt
/// qu'un unique long formulaire — chaque étape a son bouton de progression,
/// le catalogue reste borné à l'espace disponible même avec beaucoup de
/// produits.
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

  int _step = 0;
  String? _selectedCategory;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

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
    _searchCtrl.dispose();
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
          'image': product['image'],
        };
      })
      .whereType<Map<String, dynamic>>()
      .toList();

  num get _cartTotal => _cartItems.fold<num>(
    0,
    (sum, item) => sum + (item['price'] as num) * (item['quantity'] as int),
  );

  List<String> get _categories =>
      _products
          .map((p) => (p['category'] as String?)?.trim())
          .whereType<String>()
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

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

  // ── Navigation entre étapes ───────────────────────────────────────────────
  bool get _canLeaveCatalogue => _cartItems.isNotEmpty;
  bool get _canLeaveAddress => _deliveryAddress.trim().length >= 4;
  bool get _canLeavePayment => isValidSenegalMobile(_phoneCtrl.text.trim());

  void _goNext() {
    if (_step == 0 && !_canLeaveCatalogue) {
      showDemToast(context, 'Choisissez au moins un produit', isError: true);
      return;
    }
    if (_step == 1 && !_canLeaveAddress) {
      showDemToast(context, "Renseignez l'adresse de livraison", isError: true);
      return;
    }
    if (_step == 2 && !_canLeavePayment) {
      showDemToast(
        context,
        'Numéro mobile invalide (7X XXX XX XX)',
        isError: true,
      );
      return;
    }
    if (_step < 3) setState(() => _step++);
  }

  void _goBack() {
    if (_step > 0) setState(() => _step--);
  }

  // ── Soumission ─────────────────────────────────────────────────────────
  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await _dio.post(
        '/public/dem-pro/${widget.merchantId}/order-requests',
        data: {
          if (_nameCtrl.text.trim().isNotEmpty)
            'customerName': _nameCtrl.text.trim(),
          'customerPhone': _phoneCtrl.text.trim(),
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
              "Impossible d'envoyer votre commande.",
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
              'Commande envoyée !',
              style: ClientText.title.copyWith(
                color: AppColors.textDark,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$businessName va confirmer votre commande. Un livreur DEM viendra récupérer et vous livrer votre commande.',
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

  // ── Parcours en 4 étapes ────────────────────────────────────────────────
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStepIndicator(),
                const SizedBox(height: 16),
                Expanded(
                  child: StaggeredEntrance(
                    key: ValueKey(_step),
                    index: 0,
                    child: switch (_step) {
                      0 => _buildCatalogueStep(),
                      1 => _buildAddressStep(),
                      2 => _buildPaymentStep(),
                      _ => _buildReviewStep(),
                    },
                  ),
                ),
                const SizedBox(height: 16),
                _buildBottomButton(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepIndicator() => Row(
    children: [
      if (_step > 0) ...[
        GestureDetector(
          onTap: _goBack,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.lightFill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.arrow_back_rounded,
              size: 18,
              color: AppColors.textDark,
            ),
          ),
        ),
        const SizedBox(width: 12),
      ],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: i <= _step
                            ? AppColors.primary
                            : AppColors.lightFill,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Étape ${_step + 1}/4 — ${_stepLabels[_step]}',
              style: ClientText.micro.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _buildBottomButton() {
    if (_step == 0) {
      return _stepButton('Choisir l\'adresse', _canLeaveCatalogue, _goNext);
    }
    if (_step == 1) {
      return _stepButton('Continuer', _canLeaveAddress, _goNext);
    }
    if (_step == 2) {
      return _stepButton('Finaliser ma commande', _canLeavePayment, _goNext);
    }
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _submitting ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
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
                'Envoyer ma commande — ${formatFcfa(_cartTotal)}',
                style: ClientText.button,
              ),
      ),
    );
  }

  Widget _stepButton(String label, bool enabled, VoidCallback onTap) =>
      SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: enabled ? AppColors.primary : AppColors.lightFill,
            foregroundColor: enabled ? Colors.white : AppColors.textMuted,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(label, style: ClientText.button),
        ),
      );

  // ── Étape 0 : Catalogue ───────────────────────────────────────────────────
  Widget _buildCatalogueStep() {
    if (_products.isEmpty) {
      return _card(
        child: Text(
          'Ce commerçant n\'a pas encore de produits dans son catalogue.',
          style: ClientText.body.copyWith(color: AppColors.textMuted),
        ),
      );
    }
    var visible = _selectedCategory == null
        ? _products
        : _products
              .where(
                (p) =>
                    ((p['category'] as String?)?.trim().isNotEmpty ?? false
                        ? (p['category'] as String).trim()
                        : 'Autres produits') ==
                    _selectedCategory,
              )
              .toList();
    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      visible = visible
          .where(
            (p) => (p['name'] as String? ?? '').toLowerCase().contains(query),
          )
          .toList();
    }
    final showSearch = _products.length >= 8;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showSearch) ...[
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _searchQuery = v),
            style: ClientText.body.copyWith(color: AppColors.textDark),
            decoration: InputDecoration(
              hintText: 'Rechercher un produit…',
              hintStyle: ClientText.body.copyWith(color: AppColors.textMuted),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: AppColors.textMuted,
                size: 20,
              ),
              filled: true,
              fillColor: AppColors.lightFill,
              isDense: true,
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
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_categories.isNotEmpty) ...[
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _categoryChip('Tous', _selectedCategory == null),
                for (final c in _categories)
                  _categoryChip(c, _selectedCategory == c),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(
                    'Aucun produit ne correspond à votre recherche.',
                    style: ClientText.body.copyWith(color: AppColors.textMuted),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView(
                  children: [for (final p in visible) _buildProductRow(p)],
                ),
        ),
        if (_cartItems.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Text(
                  '${_cartItems.length} article${_cartItems.length > 1 ? 's' : ''}',
                  style: ClientText.bodyStrong.copyWith(
                    color: AppColors.textDark,
                  ),
                ),
                const Spacer(),
                Text(
                  formatFcfa(_cartTotal),
                  style: ClientText.bodyStrong.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _categoryChip(String label, bool active) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: GestureDetector(
      onTap: () =>
          setState(() => _selectedCategory = label == 'Tous' ? null : label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.lightFill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.lightBorder,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: ClientText.label.copyWith(
            color: active ? AppColors.primary : AppColors.textDark,
            fontWeight: active ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    ),
  );

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
          ProductThumb(imageUrl: product['image'] as String?),
          const SizedBox(width: 12),
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

  // ── Étape 1 : Adresse ─────────────────────────────────────────────────────
  Widget _buildAddressStep() => ListView(
    children: [
      _card(
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
                  _loadingGps
                      ? 'Localisation…'
                      : 'Utiliser ma position actuelle',
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: AppColors.lightFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.lightBorder),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search,
                      color: AppColors.textMuted,
                      size: 18,
                    ),
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
      ),
    ],
  );

  // ── Étape 2 : Paiement + coordonnées ─────────────────────────────────────
  Widget _buildPaymentStep() => ListView(
    children: [
      _card(
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
      ),
      const SizedBox(height: 16),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(Icons.person_outline, 'Vos coordonnées'),
            const SizedBox(height: 10),
            _FieldLabel('Votre nom (optionnel)'),
            const SizedBox(height: 4),
            _textField(_nameCtrl, 'Prénom Nom'),
            const SizedBox(height: 10),
            Row(
              children: [
                _FieldLabel('Votre téléphone'),
                Text(
                  ' *',
                  style: ClientText.label.copyWith(color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _textField(
              _phoneCtrl,
              '7X XXX XX XX',
              keyboardType: TextInputType.phone,
            ),
            if (_phoneCtrl.text.trim().isNotEmpty && !_canLeavePayment) ...[
              const SizedBox(height: 6),
              Text(
                'Numéro mobile invalide (7X XXX XX XX)',
                style: ClientText.micro.copyWith(color: AppColors.error),
              ),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _paymentChip(String value, Color dotColor, String label) {
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: ClientText.body.copyWith(
                color: active ? AppColors.primary : AppColors.textDark,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Étape 3 : Résumé ──────────────────────────────────────────────────────
  Widget _buildReviewStep() {
    final paymentLabel = _paymentMethods.firstWhere(
      (m) => m.$1 == _paymentMethod,
    );
    return ListView(
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(Icons.shopping_basket_outlined, 'Votre panier'),
              const SizedBox(height: 10),
              for (final item in _cartItems)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      ProductThumb(
                        imageUrl: item['image'] as String?,
                        size: 32,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${item['name']} × ${item['quantity']}',
                          style: ClientText.body.copyWith(
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                      Text(
                        formatFcfa(
                          (item['price'] as num) * (item['quantity'] as int),
                        ),
                        style: ClientText.label.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 20),
              Row(
                children: [
                  Text(
                    'Total',
                    style: ClientText.bodyStrong.copyWith(
                      color: AppColors.textDark,
                    ),
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
        ),
        const SizedBox(height: 16),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(Icons.location_on_outlined, 'Livraison'),
              const SizedBox(height: 8),
              Text(
                _deliveryAddress,
                style: ClientText.body.copyWith(color: AppColors.textDark),
              ),
              if (_landmarkCtrl.text.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Repère : ${_landmarkCtrl.text.trim()}',
                  style: ClientText.label.copyWith(color: AppColors.textMuted),
                ),
              ],
              if (_notesCtrl.text.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Instructions : ${_notesCtrl.text.trim()}',
                  style: ClientText.label.copyWith(color: AppColors.textMuted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(Icons.payments_outlined, 'Paiement & contact'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: paymentLabel.$2,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${paymentLabel.$3} — à la livraison',
                    style: ClientText.body.copyWith(color: AppColors.textDark),
                  ),
                ],
              ),
              if (_nameCtrl.text.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  _nameCtrl.text.trim(),
                  style: ClientText.label.copyWith(color: AppColors.textMuted),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                _phoneCtrl.text.trim(),
                style: ClientText.label.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

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
    onChanged: (_) => setState(() {}),
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
