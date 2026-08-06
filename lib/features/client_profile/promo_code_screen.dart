import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/error/app_exception.dart';
import '../../core/storage/promo_code_storage.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../../core/utils/dem_toast.dart';
import '../deliveries/data/orders_repository.dart';

String _describe(Map<String, dynamic> promo) {
  final type = promo['type'] as String?;
  final value = (promo['value'] as num?)?.toDouble();
  switch (type) {
    case 'FREE_COURSE':
      return 'Ta prochaine course éligible sera gratuite';
    case 'PERCENT_OFF':
      return '-${value?.toStringAsFixed(0)}% sur ta prochaine course éligible';
    case 'FIXED_OFF':
      return '-${value?.toStringAsFixed(0)} FCFA sur ta prochaine course éligible';
    default:
      return 'Réduction disponible';
  }
}

class PromoCodeScreen extends StatefulWidget {
  const PromoCodeScreen({super.key});

  @override
  State<PromoCodeScreen> createState() => _PromoCodeScreenState();
}

class _PromoCodeScreenState extends State<PromoCodeScreen> {
  final _repo = OrdersRepository();
  final _ctrl = TextEditingController();

  bool _loading = true;
  bool _checking = false;
  String? _error;
  Map<String, dynamic>?
  _savedPromo; // détails de l'éventuel code déjà enregistré
  List<Map<String, dynamic>> _availablePromos = [];

  @override
  void initState() {
    super.initState();
    _loadSaved();
    _loadAvailable();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadAvailable() async {
    final promos = await _repo.getAvailablePromos();
    if (mounted) setState(() => _availablePromos = promos);
  }

  Future<void> _loadSaved() async {
    final code = await PromoCodeStorage.get();
    if (code == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    // Revalide au chargement — le code enregistré a pu expirer/être désactivé
    // entre-temps côté admin.
    try {
      final promo = await _repo.validatePromoCode(code);
      if (mounted)
        setState(() {
          _savedPromo = promo;
          _loading = false;
        });
    } catch (e) {
      // `statusCode` absent = pas de réponse serveur reçue (réseau/timeout) —
      // le code est probablement toujours valide, on ne le supprime pas sur
      // la foi d'un simple problème de connexion. Seule une réponse serveur
      // explicite (400/404 : code invalide/expiré) justifie de l'oublier.
      final isDefinitivelyInvalid = e is AppException && e.statusCode != null;
      if (isDefinitivelyInvalid) await PromoCodeStorage.clear();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _apply() async {
    final code = _ctrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final promo = await _repo.validatePromoCode(code);
      await PromoCodeStorage.save(code);
      if (!mounted) return;
      setState(() {
        _savedPromo = promo;
        _checking = false;
        _ctrl.clear();
      });
      showDemToast(context, 'Code promo enregistré !');
    } catch (e) {
      if (mounted)
        setState(() {
          _checking = false;
          _error = friendlyError(e);
        });
    }
  }

  Future<void> _confirmRemove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Retirer ce code promo ?',
          style: ClientText.subtitle,
        ),
        content: const Text(
          'Il ne sera plus appliqué automatiquement à votre prochaine course.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Retirer',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await PromoCodeStorage.clear();
    if (mounted) setState(() => _savedPromo = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                      'Code promo',
                      style: ClientText.subtitle.copyWith(color: Colors.white),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                    children: [
                      if (_savedPromo != null) ...[
                        _ActivePromoCard(
                          promo: _savedPromo!,
                          onRemove: _confirmRemove,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Utiliser un autre code',
                          style: TextStyle(
                            color: AppColors.textDark,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ] else ...[
                        const Text(
                          'Vous avez un code promo ?',
                          style: TextStyle(
                            color: AppColors.textDark,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Saisissez-le ici — il sera automatiquement appliqué à votre prochaine course éligible, sans avoir à le retaper.',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _ctrl,
                              textCapitalization: TextCapitalization.characters,
                              style: const TextStyle(
                                fontSize: 15,
                                color: AppColors.textDark,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Ex : DEM20',
                                hintStyle: TextStyle(
                                  color: AppColors.textMuted.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: _checking ? null : _apply,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 15,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: _checking
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Valider',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                      // Promos auto-appliquées — aucun code à saisir, juste
                      // pour que le client sache ce qui est déjà actif pour
                      // lui plutôt que de chercher un code qui n'existe pas.
                      if (_availablePromos.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        const Text(
                          'Promos actives',
                          style: TextStyle(
                            color: AppColors.textDark,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Appliquées automatiquement, sans code à saisir.',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final promo in _availablePromos) ...[
                          _AutoPromoCard(promo: promo),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ],
                  ),
          ),
        ],
      ),
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
        border: Border.all(
          color: AppColors.successLight.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle,
                color: AppColors.successLight,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                promo['code'] as String? ?? '',
                style: const TextStyle(
                  color: AppColors.successLight,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onRemove,
                child: const Text(
                  'Retirer',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12.5,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _describe(promo),
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (promo['name'] != null) ...[
            const SizedBox(height: 2),
            Text(
              promo['name'] as String,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

// Carte informative pour une promo auto-appliquée — pas de code, pas
// d'action "Retirer" (le client ne la contrôle pas, elle s'applique ou non
// selon l'éligibilité de sa prochaine commande).
class _AutoPromoCard extends StatelessWidget {
  final Map<String, dynamic> promo;
  const _AutoPromoCard({required this.promo});

  @override
  Widget build(BuildContext context) {
    final expiresAt = DateTime.tryParse(promo['expiresAt'] as String? ?? '');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                color: AppColors.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  promo['name'] as String? ?? 'Promo',
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _describe(promo),
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (expiresAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Valable jusqu\'au ${expiresAt.day.toString().padLeft(2, '0')}/${expiresAt.month.toString().padLeft(2, '0')}/${expiresAt.year}',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
