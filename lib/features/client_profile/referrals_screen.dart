import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/error/app_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../../core/utils/price_format.dart';
import 'data/referrals_repository.dart';

/// Liste des filleuls — la carte de parrainage du profil ne montrait jusqu'ici
/// que le code (copier/partager), jamais qui l'a utilisé ni les récompenses
/// réellement gagnées.
class ReferralsScreen extends StatefulWidget {
  const ReferralsScreen({super.key});

  @override
  State<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends State<ReferralsScreen> {
  final _repo = ReferralsRepository();
  List<Map<String, dynamic>> _referrals = [];
  num _totalBonus = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repo.getMyReferrals();
      if (mounted) {
        setState(() {
          _referrals = (result['referrals'] as List)
              .cast<Map<String, dynamic>>();
          _totalBonus = (result['totalBonus'] as num?) ?? 0;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _error = friendlyError(e);
          _loading = false;
        });
    }
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
                      'Mes filleuls',
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
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.wifi_off_outlined,
                          color: AppColors.textMuted,
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _load,
                          child: const Text(
                            'Réessayer',
                            style: TextStyle(color: AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: AppColors.gradientCta,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${_referrals.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const Text(
                                      'filleul(s) inscrit(s)',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 40,
                                color: Colors.white24,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      formatFcfa(_totalBonus.toDouble()),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const Text(
                                      'gagnés au total',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_referrals.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 40),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.people_outline,
                                    color: AppColors.lightIconMuted,
                                    size: 56,
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'Aucun filleul pour le moment\nPartagez votre code depuis votre profil.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          for (final r in _referrals)
                            _ReferralTile(referral: r),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ReferralTile extends StatelessWidget {
  final Map<String, dynamic> referral;
  const _ReferralTile({required this.referral});

  @override
  Widget build(BuildContext context) {
    final referred = referral['referred'] as Map<String, dynamic>?;
    final name = referred?['name'] as String? ?? 'Utilisateur DEM';
    final bonus = (referral['bonus'] as num?) ?? 0;
    final applied = referral['isBonusApplied'] == true;
    final rawDate = referral['createdAt'] as String?;
    final joined = DateTime.tryParse(rawDate ?? '')?.toLocal();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (joined != null)
                  Text(
                    'Inscrit le ${joined.day.toString().padLeft(2, '0')}/${joined.month.toString().padLeft(2, '0')}/${joined.year}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
          if (bonus > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: (applied ? AppColors.successLight : AppColors.warning)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                applied ? '+${formatFcfa(bonus.toDouble())}' : 'En attente',
                style: TextStyle(
                  color: applied ? AppColors.successLight : AppColors.warning,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
