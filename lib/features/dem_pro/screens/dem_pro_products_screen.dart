import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../data/dem_pro_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';
import '../../../core/utils/price_format.dart';
import '../widgets/dem_pro_button.dart';

/// Catalogue de produits réutilisables — évite de retaper nom/prix à chaque
/// commande pour un commerçant qui vend souvent les mêmes articles. Trié par
/// nombre d'utilisations (voir `usageCount`), incrémenté à chaque commande
/// où le produit est choisi depuis ce catalogue.
class DemProProductsScreen extends StatefulWidget {
  final bool autoOpenForm;
  const DemProProductsScreen({super.key, this.autoOpenForm = false});
  @override
  State<DemProProductsScreen> createState() => _DemProProductsScreenState();
}

class _DemProProductsScreenState extends State<DemProProductsScreen> {
  final _repo = DemProRepository(ApiClient.dio);
  final _search = TextEditingController();

  List<Map<String, dynamic>> _products = [];
  bool _loading = true;
  bool _loadFailed = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() => _query = _search.text.toLowerCase()));
    if (widget.autoOpenForm) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showForm();
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _loadFailed = false; });
    try {
      final products = await _repo.getProducts();
      if (!mounted) return;
      setState(() { _products = products; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _loadFailed = true; });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.isEmpty) return _products;
    return _products.where((p) => (p['name'] as String? ?? '').toLowerCase().contains(_query)).toList();
  }

  Future<void> _showForm({Map<String, dynamic>? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductFormSheet(repo: _repo, existing: existing),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Supprimer ce produit ?', style: ClientText.title.copyWith(color: AppColors.textDark)),
        content: Text(
          'Voulez-vous supprimer "${product['name']}" de votre catalogue ?',
          style: ClientText.body.copyWith(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Annuler', style: ClientText.body.copyWith(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Supprimer', style: ClientText.body.copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.deleteProduct(product['id'] as String);
      _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Une erreur est survenue.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBg,
      body: SafeArea(
        child: Column(children: [

          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
            child: Row(children: [
              IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textDark, size: 18),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Mes produits', style: ClientText.headline.copyWith(color: AppColors.textDark, fontSize: 20)),
                  Text('Réutilisez-les à chaque commande', style: ClientText.label.copyWith(color: AppColors.textMuted)),
                ]),
              ),
              IconButton(
                onPressed: () => _showForm(),
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add, color: AppColors.primary, size: 22),
                ),
                tooltip: 'Ajouter un produit',
              ),
            ]),
          ),

          // ── Recherche ─────────────────────────────────────────────────────
          if (_products.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.lightBorder),
                ),
                child: TextField(
                  controller: _search,
                  style: ClientText.body.copyWith(color: AppColors.textDark, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Rechercher un produit…',
                    hintStyle: ClientText.body.copyWith(color: AppColors.textMuted, fontSize: 14),
                    prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, color: AppColors.textMuted, size: 18),
                            onPressed: () { _search.clear(); setState(() => _query = ''); },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),

          // ── Contenu ───────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _loadFailed
                    ? _buildError()
                    : RefreshIndicator(
                        color: AppColors.primary,
                        backgroundColor: Colors.white,
                        onRefresh: _load,
                        child: _filtered.isEmpty ? _buildEmpty() : _buildList(),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _buildList() => ListView.builder(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
    physics: const AlwaysScrollableScrollPhysics(),
    itemCount: _filtered.length,
    itemBuilder: (_, i) => _ProductCard(
      product: _filtered[i],
      onEdit: () => _showForm(existing: _filtered[i]),
      onDelete: () => _delete(_filtered[i]),
    ),
  );

  Widget _buildEmpty() => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.symmetric(horizontal: 32),
    children: [
      const SizedBox(height: 70),
      Container(
        width: 80, height: 80,
        margin: const EdgeInsets.symmetric(horizontal: 0),
        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.10), shape: BoxShape.circle),
        child: const Icon(Icons.inventory_2_outlined, color: AppColors.primary, size: 36),
      ),
      const SizedBox(height: 20),
      Text(
        _query.isNotEmpty ? 'Aucun résultat pour "$_query"' : 'Aucun produit enregistré',
        style: ClientText.title.copyWith(color: AppColors.textDark, fontSize: 17),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      if (_query.isEmpty)
        Text(
          'Ajoutez les produits que vous vendez le plus souvent pour les retrouver instantanément à chaque nouvelle commande.',
          style: ClientText.body.copyWith(color: AppColors.textMuted, height: 1.5),
          textAlign: TextAlign.center,
        ),
      if (_query.isEmpty) ...[
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => _showForm(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.add, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('Ajouter un produit', style: ClientText.button.copyWith(fontSize: 14)),
            ]),
          ),
        ),
      ],
    ],
  );

  Widget _buildError() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 36),
      const SizedBox(height: 12),
      Text('Impossible de charger le catalogue', style: ClientText.subtitle.copyWith(color: AppColors.textDark, fontSize: 15)),
      const SizedBox(height: 16),
      GestureDetector(
        onTap: _load,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
          child: Text('Réessayer', style: ClientText.button.copyWith(fontSize: 14)),
        ),
      ),
    ]),
  );
}

// ── Card produit ──────────────────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ProductCard({required this.product, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final name = product['name'] as String? ?? '';
    final price = product['defaultPrice'] as num?;
    final quantity = (product['quantity'] as num?)?.toInt();
    final usageCount = (product['usageCount'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.lightFill),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.inventory_2_outlined, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: ClientText.subtitle.copyWith(color: AppColors.textDark), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(children: [
                    Text(
                      price != null ? formatFcfa(price) : 'Prix non défini',
                      style: ClientText.label.copyWith(color: price != null ? AppColors.successLight : AppColors.textMuted),
                    ),
                    if (usageCount > 0) ...[
                      Text('  ·  ', style: ClientText.label.copyWith(color: AppColors.textMuted)),
                      Text('$usageCount vente${usageCount > 1 ? 's' : ''}', style: ClientText.label.copyWith(color: AppColors.textMuted)),
                    ],
                  ]),
                  if (quantity != null) ...[
                    const SizedBox(height: 3),
                    Builder(builder: (context) {
                      // Mêmes seuils que le décrément côté serveur (voir
                      // orders.service.js:LOW_STOCK_THRESHOLD) — la carte
                      // catalogue doit refléter l'urgence de la même façon
                      // que l'alerte push.
                      final isOut = quantity <= 0;
                      final isLow = !isOut && quantity <= 3;
                      final color = isOut
                          ? AppColors.error
                          : isLow
                          ? AppColors.warning
                          : AppColors.textMuted;
                      final label = isOut
                          ? 'Rupture de stock'
                          : isLow
                          ? 'Stock faible — $quantity restant${quantity > 1 ? 's' : ''}'
                          : '$quantity en stock';
                      return Row(children: [
                        Icon(
                          isOut
                              ? Icons.error_outline
                              : isLow
                              ? Icons.warning_amber_rounded
                              : Icons.inventory_outlined,
                          size: 12,
                          color: color,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          label,
                          style: ClientText.micro.copyWith(
                            color: color,
                            fontWeight: isOut || isLow ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ]);
                    }),
                  ],
                ]),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.textMuted, size: 20),
                color: AppColors.lightFill,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: _menuItem(Icons.edit_outlined, 'Modifier', AppColors.textDark)),
                  PopupMenuItem(value: 'delete', child: _menuItem(Icons.delete_outline, 'Supprimer', AppColors.error)),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, Color color) => Row(children: [
    Icon(icon, color: color, size: 18),
    const SizedBox(width: 10),
    Text(label, style: ClientText.body.copyWith(color: color)),
  ]);
}

// ── Formulaire produit (bottom sheet) ────────────────────────────────────────

class _ProductFormSheet extends StatefulWidget {
  final DemProRepository repo;
  final Map<String, dynamic>? existing;
  const _ProductFormSheet({required this.repo, this.existing});
  @override
  State<_ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<_ProductFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _quantity;
  bool _saving = false;

  // Multi-point de vente — null = disponible partout (comportement
  // historique). Chargé séparément du produit lui-même : le catalogue
  // d'adresses n'est pas toujours déjà en mémoire quand la feuille s'ouvre.
  String? _proAddressId;
  List<Map<String, dynamic>> _addresses = [];
  bool _loadingAddresses = true;

  bool get _isEdit => widget.existing != null && widget.existing!.containsKey('id');

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['name'] as String? ?? '');
    final price = e?['defaultPrice'] as num?;
    _price = TextEditingController(text: price != null ? price.toInt().toString() : '');
    final quantity = e?['quantity'] as num?;
    _quantity = TextEditingController(text: quantity != null ? quantity.toInt().toString() : '');
    _proAddressId = e?['proAddressId'] as String?;
    _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    try {
      final addresses = await widget.repo.getAddresses();
      if (mounted) setState(() {
        _addresses = addresses;
        _loadingAddresses = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingAddresses = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final priceText = _price.text.trim();
      final quantityText = _quantity.text.trim();
      final data = {
        'name': _name.text.trim(),
        'defaultPrice': priceText.isEmpty ? null : num.tryParse(priceText),
        'quantity': quantityText.isEmpty ? null : int.tryParse(quantityText),
        'proAddressId': _proAddressId,
      };
      if (_isEdit) {
        await widget.repo.updateProduct(widget.existing!['id'] as String, data);
      } else {
        await widget.repo.createProduct(data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomPadding),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: AppColors.lightBorder, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
            Text(
              _isEdit ? 'Modifier le produit' : 'Nouveau produit',
              style: ClientText.title.copyWith(color: AppColors.textDark, fontSize: 18),
            ),
            const SizedBox(height: 20),

            Text('Nom du produit', style: ClientText.label.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _name,
              autofocus: !_isEdit,
              textCapitalization: TextCapitalization.sentences,
              style: ClientText.body.copyWith(color: AppColors.textDark, fontSize: 14),
              validator: (v) => (v == null || v.trim().length < 2) ? 'Minimum 2 caractères' : null,
              decoration: InputDecoration(
                hintText: 'ex: Ceebu jën, T-shirt col rond M…',
                hintStyle: ClientText.body.copyWith(color: AppColors.textMuted),
                filled: true, fillColor: AppColors.lightFill,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.lightBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.lightBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error)),
                focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 14),

            Text('Prix par défaut (optionnel)', style: ClientText.label.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _price,
              keyboardType: TextInputType.number,
              style: ClientText.body.copyWith(color: AppColors.textDark, fontSize: 14),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final n = num.tryParse(v.trim());
                if (n == null || n <= 0) return 'Prix invalide';
                return null;
              },
              decoration: InputDecoration(
                hintText: 'ex: 2500',
                suffixText: 'FCFA',
                suffixStyle: ClientText.body.copyWith(color: AppColors.textMuted),
                hintStyle: ClientText.body.copyWith(color: AppColors.textMuted),
                filled: true, fillColor: AppColors.lightFill,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.lightBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.lightBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error)),
                focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Vous pourrez toujours ajuster le prix au moment de la commande.',
              style: ClientText.micro.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),

            Text('Quantité disponible (optionnel)', style: ClientText.label.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _quantity,
              keyboardType: TextInputType.number,
              style: ClientText.body.copyWith(color: AppColors.textDark, fontSize: 14),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final n = int.tryParse(v.trim());
                if (n == null || n < 0) return 'Quantité invalide';
                return null;
              },
              decoration: InputDecoration(
                hintText: 'ex: 20',
                suffixText: 'en stock',
                suffixStyle: ClientText.body.copyWith(color: AppColors.textMuted),
                hintStyle: ClientText.body.copyWith(color: AppColors.textMuted),
                filled: true, fillColor: AppColors.lightFill,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.lightBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.lightBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error)),
                focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Laissez vide si vous ne suivez pas votre stock depuis l\'app.',
              style: ClientText.micro.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),

            // ── Point de vente (multi-site) — masqué tant qu'aucune adresse
            // n'est enregistrée : rien à choisir, pas la peine d'encombrer.
            if (!_loadingAddresses && _addresses.isNotEmpty) ...[
              Text('Point de vente', style: ClientText.label.copyWith(color: AppColors.textMuted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ProAddressChip(
                    label: 'Tous',
                    active: _proAddressId == null,
                    onTap: () => setState(() => _proAddressId = null),
                  ),
                  for (final a in _addresses)
                    _ProAddressChip(
                      label: a['label'] as String? ?? '—',
                      active: _proAddressId == a['id'],
                      onTap: () => setState(() => _proAddressId = a['id'] as String?),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Ce produit n\'apparaîtra que pour les commandes expédiées depuis ce point de vente.',
                style: ClientText.micro.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 14),
            ],
            const SizedBox(height: 10),

            DemProButton(
              label: _isEdit ? 'Enregistrer les modifications' : 'Ajouter au catalogue',
              loading: _saving,
              onTap: _submit,
            ),
          ]),
        ),
      ),
    );
  }
}

class _ProAddressChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ProAddressChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: active ? AppColors.primary : AppColors.lightFill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? AppColors.primary : AppColors.lightBorder),
      ),
      child: Text(
        label,
        style: ClientText.body.copyWith(
          color: active ? Colors.white : AppColors.textDark,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ),
  );
}
