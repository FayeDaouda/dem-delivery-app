import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../data/dem_pro_repository.dart';
import '../theme/dem_pro_colors.dart';
import '../theme/dem_pro_text.dart';
import '../utils/dem_pro_format.dart';
import '../widgets/dem_pro_button.dart';

/// Catalogue de produits réutilisables — évite de retaper nom/prix à chaque
/// commande pour un commerçant qui vend souvent les mêmes articles. Trié par
/// nombre d'utilisations (voir `usageCount`), incrémenté à chaque commande
/// où le produit est choisi depuis ce catalogue.
class DemProProductsScreen extends StatefulWidget {
  const DemProProductsScreen({super.key});
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
        backgroundColor: DemProColors.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Supprimer ce produit ?', style: DemProText.title.copyWith(color: DemProColors.text)),
        content: Text(
          'Voulez-vous supprimer "${product['name']}" de votre catalogue ?',
          style: DemProText.body.copyWith(color: DemProColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Annuler', style: DemProText.body.copyWith(color: DemProColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Supprimer', style: DemProText.body.copyWith(color: DemProColors.danger)),
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
      backgroundColor: DemProColors.bg,
      body: SafeArea(
        child: Column(children: [

          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
            child: Row(children: [
              IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_ios_new, color: DemProColors.text, size: 18),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Mes produits', style: DemProText.headline.copyWith(color: DemProColors.text, fontSize: 20)),
                  Text('Réutilisez-les à chaque commande', style: DemProText.caption.copyWith(color: DemProColors.muted)),
                ]),
              ),
              IconButton(
                onPressed: () => _showForm(),
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: DemProColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add, color: DemProColors.accent, size: 22),
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
                  color: DemProColors.bg2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: DemProColors.bg4),
                ),
                child: TextField(
                  controller: _search,
                  style: DemProText.body.copyWith(color: DemProColors.text, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Rechercher un produit…',
                    hintStyle: DemProText.body.copyWith(color: DemProColors.muted, fontSize: 14),
                    prefixIcon: const Icon(Icons.search, color: DemProColors.muted, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, color: DemProColors.muted, size: 18),
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
                ? const Center(child: CircularProgressIndicator(color: DemProColors.accent))
                : _loadFailed
                    ? _buildError()
                    : RefreshIndicator(
                        color: DemProColors.accent,
                        backgroundColor: DemProColors.bg2,
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
        decoration: BoxDecoration(color: DemProColors.accent.withValues(alpha: 0.10), shape: BoxShape.circle),
        child: const Icon(Icons.inventory_2_outlined, color: DemProColors.accent, size: 36),
      ),
      const SizedBox(height: 20),
      Text(
        _query.isNotEmpty ? 'Aucun résultat pour "$_query"' : 'Aucun produit enregistré',
        style: DemProText.title.copyWith(color: DemProColors.text, fontSize: 17),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      if (_query.isEmpty)
        Text(
          'Ajoutez les produits que vous vendez le plus souvent pour les retrouver instantanément à chaque nouvelle commande.',
          style: DemProText.body.copyWith(color: DemProColors.muted, height: 1.5),
          textAlign: TextAlign.center,
        ),
      if (_query.isEmpty) ...[
        const SizedBox(height: 24),
        GestureDetector(
          onTap: () => _showForm(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(color: DemProColors.accent, borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.add, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text('Ajouter un produit', style: DemProText.button.copyWith(fontSize: 14)),
            ]),
          ),
        ),
      ],
    ],
  );

  Widget _buildError() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.wifi_off_rounded, color: DemProColors.muted, size: 36),
      const SizedBox(height: 12),
      Text('Impossible de charger le catalogue', style: DemProText.subtitle.copyWith(color: DemProColors.text, fontSize: 15)),
      const SizedBox(height: 16),
      GestureDetector(
        onTap: _load,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(color: DemProColors.accent, borderRadius: BorderRadius.circular(10)),
          child: Text('Réessayer', style: DemProText.button.copyWith(fontSize: 14)),
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
    final usageCount = (product['usageCount'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: DemProColors.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DemProColors.bg3),
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
                  color: DemProColors.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.inventory_2_outlined, color: DemProColors.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: DemProText.subtitle.copyWith(color: DemProColors.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(children: [
                    Text(
                      price != null ? DemProFormat.fcfa(price) : 'Prix non défini',
                      style: DemProText.caption.copyWith(color: price != null ? DemProColors.success : DemProColors.muted),
                    ),
                    if (usageCount > 0) ...[
                      Text('  ·  ', style: DemProText.caption.copyWith(color: DemProColors.muted)),
                      Text('$usageCount vente${usageCount > 1 ? 's' : ''}', style: DemProText.caption.copyWith(color: DemProColors.muted)),
                    ],
                  ]),
                ]),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: DemProColors.muted, size: 20),
                color: DemProColors.bg3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: _menuItem(Icons.edit_outlined, 'Modifier', DemProColors.text)),
                  PopupMenuItem(value: 'delete', child: _menuItem(Icons.delete_outline, 'Supprimer', DemProColors.danger)),
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
    Text(label, style: DemProText.body.copyWith(color: color)),
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
  bool _saving = false;

  bool get _isEdit => widget.existing != null && widget.existing!.containsKey('id');

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?['name'] as String? ?? '');
    final price = e?['defaultPrice'] as num?;
    _price = TextEditingController(text: price != null ? price.toInt().toString() : '');
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final priceText = _price.text.trim();
      final data = {
        'name': _name.text.trim(),
        'defaultPrice': priceText.isEmpty ? null : num.tryParse(priceText),
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
        SnackBar(content: Text(e.toString()), backgroundColor: DemProColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: DemProColors.bg2,
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
                  decoration: BoxDecoration(color: DemProColors.bg4, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
            Text(
              _isEdit ? 'Modifier le produit' : 'Nouveau produit',
              style: DemProText.title.copyWith(color: DemProColors.text, fontSize: 18),
            ),
            const SizedBox(height: 20),

            Text('Nom du produit', style: DemProText.caption.copyWith(color: DemProColors.muted)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _name,
              autofocus: !_isEdit,
              textCapitalization: TextCapitalization.sentences,
              style: DemProText.body.copyWith(color: DemProColors.text, fontSize: 14),
              validator: (v) => (v == null || v.trim().length < 2) ? 'Minimum 2 caractères' : null,
              decoration: InputDecoration(
                hintText: 'ex: Ceebu jën, T-shirt col rond M…',
                hintStyle: DemProText.body.copyWith(color: DemProColors.muted),
                filled: true, fillColor: DemProColors.bg3,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.bg4)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.bg4)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.accent, width: 1.5)),
                errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.danger)),
                focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.danger, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 14),

            Text('Prix par défaut (optionnel)', style: DemProText.caption.copyWith(color: DemProColors.muted)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _price,
              keyboardType: TextInputType.number,
              style: DemProText.body.copyWith(color: DemProColors.text, fontSize: 14),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final n = num.tryParse(v.trim());
                if (n == null || n <= 0) return 'Prix invalide';
                return null;
              },
              decoration: InputDecoration(
                hintText: 'ex: 2500',
                suffixText: 'FCFA',
                suffixStyle: DemProText.body.copyWith(color: DemProColors.muted),
                hintStyle: DemProText.body.copyWith(color: DemProColors.muted),
                filled: true, fillColor: DemProColors.bg3,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.bg4)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.bg4)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.accent, width: 1.5)),
                errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.danger)),
                focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: DemProColors.danger, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Vous pourrez toujours ajuster le prix au moment de la commande.',
              style: DemProText.micro.copyWith(color: DemProColors.muted),
            ),
            const SizedBox(height: 24),

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
