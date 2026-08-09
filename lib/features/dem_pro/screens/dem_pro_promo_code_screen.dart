import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_exception.dart';
import '../../../core/storage/promo_code_storage.dart';
import '../../../core/utils/dem_toast.dart';
import '../../deliveries/data/orders_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';

String _describe(Map<String, dynamic> promo) {
  final type = promo['type'] as String?;
  final value = (promo['value'] as num?)?.toDouble();
  switch (type) {
    case 'FREE_COURSE': return 'Votre prochaine livraison éligible sera gratuite';
    case 'PERCENT_OFF':  return '-${value?.toStringAsFixed(0)}% sur votre prochaine livraison éligible';
    case 'FIXED_OFF':    return '-${value?.toStringAsFixed(0)} FCFA sur votre prochaine livraison éligible';
    default: return 'Réduction disponible';
  }
}

class DemProPromoCodeScreen extends StatefulWidget {
  const DemProPromoCodeScreen({super.key});

  @override
  State<DemProPromoCodeScreen> createState() => _DemProPromoCodeScreenState();
}

class _DemProPromoCodeScreenState extends State<DemProPromoCodeScreen> {
  final _repo = OrdersRepository();
  final _ctrl = TextEditingController();

  bool _loading = true;
  bool _checking = false;
  String? _error;
  Map<String, dynamic>? _savedPromo;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    final code = await PromoCodeStorage.get();
    if (code == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final promo = await _repo.validatePromoCode(code);
      if (mounted) setState(() { _savedPromo = promo; _loading = false; });
    } catch (_) {
      await PromoCodeStorage.clear();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _apply() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty) return;
    setState(() { _checking = true; _error = null; });
    try {
      final promo = await _repo.validatePromoCode(code);
      await PromoCodeStorage.save(code);
      if (!mounted) return;
      setState(() { _savedPromo = promo; _checking = false; _ctrl.clear(); });
      showDemToast(context, 'Code promo enregistré !');
    } catch (e) {
      if (mounted) setState(() { _checking = false; _error = friendlyError(e); });
    }
  }

  Future<void> _remove() async {
    await PromoCodeStorage.clear();
    if (mounted) setState(() => _savedPromo = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBg,
      body: Column(children: [
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 20),
              child: Row(children: [
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                ),
                Text('Code promo', style: ClientText.title.copyWith(color: Colors.white, fontSize: 18)),
              ]),
            ),
          ),
        ),
        Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                    children: [
                      if (_savedPromo != null) ...[
                        _ActivePromoCard(promo: _savedPromo!, onRemove: _remove),
                        const SizedBox(height: 24),
                        Text('Utiliser un autre code',
                            style: ClientText.bodyStrong.copyWith(color: AppColors.textDark)),
                        const SizedBox(height: 12),
                      ] else ...[
                        Text('Vous avez un code promo ?',
                            style: ClientText.headline.copyWith(color: AppColors.textDark, fontSize: 17)),
                        const SizedBox(height: 6),
                        Text(
                          'Saisissez-le ici — il sera automatiquement appliqué à votre prochaine commande éligible, sans avoir à le retaper.',
                          style: ClientText.label.copyWith(color: AppColors.textMuted, height: 1.4),
                        ),
                        const SizedBox(height: 20),
                      ],
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            textCapitalization: TextCapitalization.characters,
                            style: ClientText.subtitle.copyWith(color: AppColors.textDark),
                            decoration: InputDecoration(
                              hintText: 'Ex : DEM20',
                              hintStyle: ClientText.body.copyWith(color: AppColors.textMuted),
                              filled: true,
                              fillColor: AppColors.lightFill,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: _checking ? null : _apply,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
                            child: _checking
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Text('Valider', style: ClientText.bodyStrong.copyWith(color: Colors.white)),
                          ),
                        ),
                      ]),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(_error!, style: ClientText.label.copyWith(color: AppColors.error)),
                      ],
                    ],
                  ),
        ),
      ]),
    );
  }
}

class _ActivePromoCard extends StatelessWidget {
  final Map<String, dynamic> promo;
  final VoidCallback onRemove;
  const _ActivePromoCard({required this.promo, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.successLight.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.successLight.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.check_circle, color: AppColors.successLight, size: 20),
            const SizedBox(width: 8),
            Text(promo['code'] as String? ?? '',
                style: ClientText.bodyStrong.copyWith(color: AppColors.successLight, letterSpacing: 0.5)),
            const Spacer(),
            GestureDetector(
              onTap: onRemove,
              child: Text('Retirer', style: ClientText.label.copyWith(color: AppColors.textMuted, decoration: TextDecoration.underline)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(_describe(promo), style: ClientText.body.copyWith(color: AppColors.textDark, fontWeight: FontWeight.w600)),
          if (promo['name'] != null) ...[
            const SizedBox(height: 2),
            Text(promo['name'] as String, style: ClientText.label.copyWith(color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }
}
