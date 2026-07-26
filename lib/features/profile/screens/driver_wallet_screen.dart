import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/error/app_exception.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/storage/auth_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';
import '../../../core/utils/dem_toast.dart';
import '../../../shared/widgets/gradient_sheet.dart';
import '../../../shared/widgets/operator_picker_sheet.dart';
import '../../../shared/widgets/payment_operator_badge.dart';
import '../../../shared/widgets/samirpay_payment_sheet.dart';
import '../../../shared/widgets/swipe_to_confirm.dart';
import '../data/profile_repository.dart';
import '../data/wallet_repository.dart';

class DriverWalletScreen extends StatefulWidget {
  const DriverWalletScreen({super.key});

  @override
  State<DriverWalletScreen> createState() => _DriverWalletScreenState();
}

class _DriverWalletScreenState extends State<DriverWalletScreen> {
  final _walletRepo  = WalletRepository();
  final _profileRepo = ProfileRepository();

  bool _loading = true;
  String? _error;
  double _balance = 0;
  double _withdrawableBalance = 0;
  Map<String, double> _receivedByOperator = const {'WAVE': 0, 'ORANGE_MONEY': 0};
  List<Map<String, dynamic>> _transactions = [];
  Map<String, dynamic>? _forfaitStatus;
  String? _vehicleType;

  // ── Promotion sur la passe (voir promo.service.js côté serveur) ─────────
  double? _forfaitDiscountAmount;
  String? _forfaitPromoLabel;
  String? _forfaitPromoError;
  bool _checkingForfaitPromo = false;
  bool _activatingFreeForfait = false;
  final _forfaitPromoCodeCtrl = TextEditingController();

  // ── Pagination historique ────────────────────────────────────────────────
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;

  // ── Filtre historique ────────────────────────────────────────────────────
  _TxFilter _filter = _TxFilter.all;

  StreamSubscription<Map<String, dynamic>>? _walletSub;

  @override
  void initState() {
    super.initState();
    _load();
    // Le webhook SamirPay met à jour le solde côté serveur de façon
    // asynchrone (recharge ou retrait) — on écoute l'événement plutôt que
    // de faire du polling.
    _walletSub = SocketService.instance.onWalletUpdated.listen((event) {
      final balance = (event['balance'] as num?)?.toDouble();
      if (balance != null && mounted) setState(() => _balance = balance);
    });
  }

  @override
  void dispose() {
    _walletSub?.cancel();
    _forfaitPromoCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final user = await AuthStorage.getUser();
      final results = await Future.wait([
        _walletRepo.getWalletSummary(),
        _profileRepo.getForfaitStatus(),
      ]);
      final summary = results[0] as Map<String, dynamic>;
      final forfait = results[1];
      if (!mounted) return;
      setState(() {
        _vehicleType         = user?['vehicleType'] as String?;
        _balance             = (summary['balance'] as num?)?.toDouble() ?? 0;
        _withdrawableBalance = (summary['withdrawableBalance'] as num?)?.toDouble() ?? 0;
        final byOp = summary['receivedByOperator'] as Map<String, dynamic>?;
        _receivedByOperator  = {
          'WAVE':         (byOp?['WAVE'] as num?)?.toDouble() ?? 0,
          'ORANGE_MONEY': (byOp?['ORANGE_MONEY'] as num?)?.toDouble() ?? 0,
        };
        _transactions        = (summary['recentTransactions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _forfaitStatus       = forfait;
        _loading             = false;
        _page                = 1;
        _hasMore             = _transactions.length >= 20;
      });
      _checkForfaitPromo();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = friendlyError(e); });
    }
  }

  // Vérification silencieuse — une campagne DRIVER auto-appliquée peut
  // exister ; aucune erreur affichée si non (cas normal).
  Future<void> _checkForfaitPromo() async {
    try {
      final result = await _walletRepo.getForfaitPromoPreview();
      if (!mounted || result == null) return;
      final discount = (result['discountAmount'] as num?)?.toDouble() ?? 0;
      if (discount <= 0) return;
      setState(() {
        _forfaitDiscountAmount = discount;
        _forfaitPromoLabel     = result['promoCode'] as String?;
      });
    } catch (_) {} // jamais bloquant
  }

  Future<void> _applyForfaitPromoCode() async {
    final code = _forfaitPromoCodeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() { _checkingForfaitPromo = true; _forfaitPromoError = null; });
    try {
      final result = await _walletRepo.getForfaitPromoPreview(code: code);
      if (!mounted) return;
      final discount = (result?['discountAmount'] as num?)?.toDouble() ?? 0;
      setState(() {
        _forfaitDiscountAmount = discount > 0 ? discount : null;
        _forfaitPromoLabel     = result?['promoCode'] as String?;
        _checkingForfaitPromo  = false;
      });
      if (discount > 0) showDemToast(context, 'Code promo appliqué !');
    } catch (e) {
      if (mounted) {
        setState(() {
          _checkingForfaitPromo = false;
          _forfaitPromoError = friendlyError(e);
          _forfaitDiscountAmount = null;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final result = await _walletRepo.getWalletTransactions(page: nextPage);
      final more = (result['transactions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final total = (result['total'] as num?)?.toInt() ?? _transactions.length;
      if (!mounted) return;
      setState(() {
        _transactions.addAll(more);
        _page = nextPage;
        _hasMore = _transactions.length < total && more.isNotEmpty;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  List<Map<String, dynamic>> get _filteredTransactions {
    if (_filter == _TxFilter.all) return _transactions;
    return _transactions.where((t) => _filter.types.contains(t['type'] as String? ?? '')).toList();
  }

  double get _forfaitAmount {
    final f = _forfaitStatus;
    if (f == null) return 0;
    final isVoiture = _vehicleType == 'VOITURE';
    final amount = isVoiture ? f['amountM3'] : f['amount'];
    return (amount as num?)?.toDouble() ?? 0;
  }

  // Estimation affichée avant confirmation — le montant réel est toujours
  // recalculé côté serveur (voir forfait.service.js:prepareForfaitPurchase).
  double get _forfaitAmountAfterDiscount =>
      (_forfaitAmount - (_forfaitDiscountAmount ?? 0)).clamp(0, double.infinity);

  // Paie la passe directement via SamirPay, sans passer par une recharge
  // générale du wallet — le montant exact de la passe est payé et active
  // automatiquement dès confirmation (voir forfait.service.js côté serveur).
  Future<void> _payForfaitOnline() async {
    // Uniquement si saisi manuellement et validé — une promo auto-appliquée
    // n'a pas besoin d'être renvoyée, le serveur la retrouve tout seul.
    final manualCode = _forfaitPromoError == null && _forfaitPromoCodeCtrl.text.trim().isNotEmpty
        ? _forfaitPromoCodeCtrl.text.trim()
        : null;

    // Réduction couvrant 100% du prix : rien à payer, donc pas de flux Wave/
    // Orange Money — SamirPay ne peut pas traiter un encaissement de 0 FCFA.
    // On active directement et le livreur n'a aucune étape supplémentaire.
    if (_forfaitAmountAfterDiscount <= 0) {
      if (_activatingFreeForfait) return;
      setState(() => _activatingFreeForfait = true);
      try {
        final result = await _walletRepo.activateFreeForfait(code: manualCode);
        if (!mounted) return;
        showDemToast(
          context,
          result['alreadyActive'] == true ? 'Votre passe du jour est déjà active.' : 'Passe activée !',
        );
        await _load();
      } catch (e) {
        if (mounted) showDemToast(context, friendlyError(e));
      } finally {
        if (mounted) setState(() => _activatingFreeForfait = false);
      }
      return;
    }

    final operatorName = await chooseOperator(context, title: 'Payer ma passe avec');
    if (operatorName == null || !mounted) return;

    await SamirpayPaymentSheet.show(
      context,
      amount: _forfaitAmountAfterDiscount.toInt(),
      title: 'Paiement de la passe journalière',
      initPayment: () async {
        final result = await _walletRepo.payForfaitOnline(operatorName, promoCode: manualCode);
        if (result['alreadyActive'] == true) {
          throw AppException('Votre passe du jour est déjà active.');
        }
        return result;
      },
      confirmationStream: SocketService.instance.onWalletUpdated,
      matchesConfirmation: (event, payment) => event['orderRef'] == payment['orderRef'],
      onSuccess: () {
        showDemToast(context, 'Passe activée !');
        _load();
      },
    );
  }

  Future<void> _openCashout() async {
    if (_withdrawableBalance <= 0) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          icon: const Icon(Icons.info_outline, color: AppColors.primary, size: 32),
          title: const Text('Aucun solde retirable',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16), textAlign: TextAlign.center),
          content: const Text(
            'Seuls les paiements encaissés en ligne par DEM (Wave, Orange Money) sont retirables ici. '
            'Les livraisons payées en espèces sont déjà dans votre poche — il n\'y a donc rien à retirer pour le moment.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Compris', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      return;
    }
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CashoutSheet(repo: _walletRepo, withdrawableBalance: _withdrawableBalance),
    );
    // Le toast (succès ou vérification en cours) est déjà affiché par la
    // feuille elle-même avant de se fermer — voir _CashoutSheetState._submit.
    if (done == true && mounted) _load();
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
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                    ),
                    const Spacer(),
                    Text('Portefeuille',
                        style: ClientText.subtitle.copyWith(color: Colors.white)),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.wifi_off_outlined, color: AppColors.textMuted, size: 48),
                            const SizedBox(height: 12),
                            Text(_error!,
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                                textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: _load,
                              child: const Text('Réessayer', style: TextStyle(color: AppColors.primary)),
                            ),
                          ],
                        ),
                      )
                    : Builder(builder: (context) {
                        // Quand le clavier s'ouvre (ex. saisie du code promo),
                        // le bloc fixe seul peut dépasser l'espace restant :
                        // on le rend alors scrollable et on masque l'historique
                        // (non pertinent pendant la saisie) plutôt que de
                        // laisser l'Expanded passer en espace négatif.
                        final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
                        if (keyboardOpen) {
                          return SingleChildScrollView(
                            padding: EdgeInsets.only(
                              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                            ),
                            child: _buildWalletTopSection(),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildWalletTopSection(),
                            const SizedBox(height: 10),
                            // ── Seule cette liste défile — le bloc au-dessus reste fixe ──
                            Expanded(child: _buildHistoryList()),
                          ],
                        );
                      }),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletTopSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BalanceCard(
            balance: _balance,
            withdrawableBalance: _withdrawableBalance,
            receivedByOperator: _receivedByOperator,
          ),
          const SizedBox(height: 12),
          _WalletActionButton(
            icon: Icons.arrow_circle_up_outlined,
            label: 'Retirer mes gains',
            onTap: _openCashout,
          ),
          const SizedBox(height: 16),
          _buildForfaitSection(),
          const SizedBox(height: 24),
          const Text('Historique',
              style: TextStyle(color: AppColors.textDark, fontSize: 15, fontWeight: FontWeight.w700)),
          if (_transactions.isNotEmpty) ...[
            const SizedBox(height: 10),
            _TxFilterBar(
              selected: _filter,
              onChanged: (f) => setState(() => _filter = f),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: _transactions.isEmpty
          ? ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: const [
                SizedBox(height: 24),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_outlined, color: AppColors.lightIconMuted, size: 56),
                      SizedBox(height: 10),
                      Text('Aucune transaction pour le moment',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            )
          : _filteredTransactions.isEmpty
              ? ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    const SizedBox(height: 24),
                    Center(
                      child: Text('Aucune transaction dans cette catégorie',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: _filteredTransactions.length +
                      (_filter == _TxFilter.all && _hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index < _filteredTransactions.length) {
                      return _TransactionTile(transaction: _filteredTransactions[index]);
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Center(
                        child: TextButton(
                          onPressed: _loadingMore ? null : _loadMore,
                          child: _loadingMore
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                )
                              : const Text('Charger plus',
                                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildForfaitSection() {
    final forfait = _forfaitStatus;
    final active = forfait?['active'] == true;
    final todayCharged = forfait?['todayCharged'] == true;

    if (!active) {
      return _InfoBanner(
        icon: Icons.info_outline,
        message: 'Le forfait journalier n\'est pas encore activé sur la plateforme.',
      );
    }
    if (todayCharged) {
      final expiresAt = DateTime.tryParse(forfait?['passExpiresAt'] as String? ?? '');
      return _ActivePassBanner(expiresAt: expiresAt);
    }
    // La passe se paie toujours en direct via Wave/Orange Money — jamais
    // depuis le solde du wallet (plus de recharge générale, voir suppression
    // de _openTopup) : elle s'active automatiquement dès confirmation SamirPay.
    final discount = _forfaitDiscountAmount ?? 0;
    final displayAmount = _forfaitAmountAfterDiscount;
    final baseMessage = 'Payez votre passe directement via Wave ou Orange Money — elle s\'active automatiquement dès confirmation.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoBanner(
          icon: Icons.confirmation_number_outlined,
          message: discount > 0
              ? '$baseMessage\nRéduction : -${discount.toStringAsFixed(0)} FCFA'
                  '${_forfaitPromoLabel != null ? ' ($_forfaitPromoLabel)' : ''}'
              : baseMessage,
          color: discount > 0 ? AppColors.successLight : AppColors.primary,
          actionLabel: _activatingFreeForfait
              ? 'Activation...'
              : displayAmount <= 0
                  ? 'Activer ma passe (gratuite)'
                  : 'Payer ma passe (${displayAmount.toStringAsFixed(0)} FCFA)',
          onAction: _activatingFreeForfait ? null : _payForfaitOnline,
        ),
        const SizedBox(height: 10),
        _buildForfaitPromoCodeField(),
      ],
    );
  }

  Widget _buildForfaitPromoCodeField() {
    final applied = _forfaitDiscountAmount != null && _forfaitDiscountAmount! > 0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _forfaitPromoCodeCtrl,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(fontSize: 13, color: AppColors.textDark),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Code promo passe (optionnel)',
                  hintStyle: TextStyle(color: AppColors.textMuted.withValues(alpha: 0.8), fontSize: 13),
                  filled: true,
                  fillColor: AppColors.lightBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _checkingForfaitPromo ? null : _applyForfaitPromoCode,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: (applied ? AppColors.successLight : AppColors.primary).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _checkingForfaitPromo
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                    : Text(
                        applied ? 'Appliqué ✓' : 'Appliquer',
                        style: TextStyle(
                          color: applied ? AppColors.successLight : AppColors.primary,
                          fontSize: 13, fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ]),
          if (_forfaitPromoError != null) ...[
            const SizedBox(height: 4),
            Text(_forfaitPromoError!, style: const TextStyle(color: AppColors.error, fontSize: 11.5)),
          ],
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final double balance;
  final double withdrawableBalance;
  final Map<String, double> receivedByOperator;
  const _BalanceCard({
    required this.balance,
    required this.withdrawableBalance,
    this.receivedByOperator = const {'WAVE': 0, 'ORANGE_MONEY': 0},
  });

  @override
  Widget build(BuildContext context) {
    // Le solde total inclut les gains des livraisons payées cash (déjà en
    // poche) — seul `withdrawableBalance` (argent réellement collecté par DEM
    // via SamirPay) peut être retiré. Les deux ne coïncident donc pas tant
    // qu'un livreur n'a encaissé que du cash, ce qui est le cas le plus
    // fréquent au lancement — l'explication évite la confusion "pourquoi je
    // ne peux pas tout retirer ?".
    final hasGap = balance - withdrawableBalance > 0.5;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.gradientDialog,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Solde total',
              style: ClientText.body.copyWith(color: Colors.white70)),
          const SizedBox(height: 8),
          Text('${balance.toStringAsFixed(0)} FCFA',
              style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${withdrawableBalance.toStringAsFixed(0)} FCFA retirables',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          if (hasGap) ...[
            const SizedBox(height: 8),
            Text(
              'Les livraisons payées en espèces sont déjà dans votre poche — seuls les paiements encaissés en ligne par DEM sont retirables ici.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 11.5, height: 1.4),
            ),
          ],
          if ((receivedByOperator['WAVE'] ?? 0) > 0 || (receivedByOperator['ORANGE_MONEY'] ?? 0) > 0) ...[
            const SizedBox(height: 14),
            Text('Reçu de vos clients en ligne',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.70), fontSize: 11.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(children: [
              _OperatorReceivedChip(operatorName: 'WAVE', amount: receivedByOperator['WAVE'] ?? 0),
              const SizedBox(width: 10),
              _OperatorReceivedChip(operatorName: 'ORANGE_MONEY', amount: receivedByOperator['ORANGE_MONEY'] ?? 0),
            ]),
          ],
        ],
      ),
    );
  }
}

class _OperatorReceivedChip extends StatelessWidget {
  final String operatorName;
  final double amount;
  const _OperatorReceivedChip({required this.operatorName, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          PaymentOperatorBadge(operatorName: operatorName, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${amount.toStringAsFixed(0)} FCFA',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}

// ── Filtre d'historique ──────────────────────────────────────────────────────

enum _TxFilter {
  all(label: 'Tout', types: []),
  deliveries(label: 'Livraisons', types: ['CREDIT_DELIVERY']),
  topups(label: 'Recharges', types: ['CREDIT_TOPUP']),
  cashouts(label: 'Retraits', types: ['DEBIT_CASHOUT']),
  forfait(label: 'Passe', types: ['DEBIT_FORFAIT']);

  final String label;
  final List<String> types;
  const _TxFilter({required this.label, required this.types});
}

class _TxFilterBar extends StatelessWidget {
  final _TxFilter selected;
  final ValueChanged<_TxFilter> onChanged;
  const _TxFilterBar({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _TxFilter.values.map((f) {
          final active = f == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChanged(f),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: active ? AppColors.primary : AppColors.lightBorder),
                ),
                child: Text(f.label,
                    style: TextStyle(
                      color: active ? Colors.white : AppColors.textDark,
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    )),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _InfoBanner({
    required this.icon,
    required this.message,
    this.color = AppColors.primary,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: ClientText.body.copyWith(color: color))),
          ]),
          if (actionLabel != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(actionLabel!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Bannière "passe active" avec compte à rebours jusqu'à expiration — la
// couleur se dégrade (vert → ambre → rouge) à mesure que l'échéance
// approche, pour que le livreur pense à la renouveler avant de se retrouver
// bloqué hors ligne en pleine course.
class _ActivePassBanner extends StatefulWidget {
  final DateTime? expiresAt;
  const _ActivePassBanner({required this.expiresAt});

  @override
  State<_ActivePassBanner> createState() => _ActivePassBannerState();
}

class _ActivePassBannerState extends State<_ActivePassBanner> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expiresAt = widget.expiresAt;
    final remaining = expiresAt?.difference(DateTime.now());

    String? timeLabel;
    Color timeColor = AppColors.successLight;
    if (remaining != null) {
      if (remaining.isNegative) {
        timeLabel = 'Expirée';
        timeColor = AppColors.error;
      } else {
        final h = remaining.inHours;
        final m = remaining.inMinutes % 60;
        timeLabel = h > 0 ? '${h}h${m.toString().padLeft(2, '0')} restantes' : '$m min restantes';
        if (remaining.inHours < 2) {
          timeColor = AppColors.error;
        } else if (remaining.inHours < 6) {
          timeColor = AppColors.warning;
        } else {
          timeColor = AppColors.successLight;
        }
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: Row(children: [
        const Icon(Icons.check_circle_outline, color: AppColors.successLight, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Votre passe du jour est active.',
              style: ClientText.body.copyWith(color: AppColors.successLight)),
        ),
        if (timeLabel != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: timeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.timer_outlined, size: 13, color: timeColor),
              const SizedBox(width: 4),
              Text(timeLabel,
                  style: TextStyle(color: timeColor, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Map<String, dynamic> transaction;
  const _TransactionTile({required this.transaction});

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year}  ${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  // Statut d'un retrait SamirPay — null pour tout le reste (recharge,
  // livraison, forfait), qui n'a pas cette notion d'état intermédiaire.
  (String, Color)? _cashoutStatus() {
    if (transaction['type'] != 'DEBIT_CASHOUT') return null;
    if (transaction['needsManualReview'] == true) {
      return ('Vérification en cours', AppColors.pending);
    }
    return switch (transaction['samirpayStatus'] as String?) {
      'PENDING' => ('En cours', AppColors.pending),
      'FAILED'  => ('Échoué — remboursé', AppColors.error),
      _         => null, // SUCCESS ou ancien retrait pré-SamirPay : rien à signaler
    };
  }

  @override
  Widget build(BuildContext context) {
    final type = transaction['type'] as String? ?? '';
    // CREDIT_DELIVERY et CREDIT_TOPUP sont tous les deux des crédits — on se
    // base sur le préfixe plutôt que sur une seule valeur en dur (bug corrigé
    // lors de l'ajout de la recharge/retrait SamirPay).
    final isCredit = type.startsWith('CREDIT_');
    final amount = (transaction['amount'] as num?)?.toDouble() ?? 0;
    final description = transaction['description'] as String? ?? '';
    final createdAt = DateTime.tryParse(transaction['createdAt'] as String? ?? '');
    final color = isCredit ? AppColors.successLight : AppColors.error;
    final isOnlinePayment = type == 'CREDIT_DELIVERY' && transaction['paymentMethod'] == 'online';
    final cashoutStatus = _cashoutStatus();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(
            isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
            color: color, size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(description,
                      style: ClientText.body.copyWith(color: AppColors.textDark),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (isOnlinePayment) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('En ligne',
                        style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              Text(_formatDate(createdAt), style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              if (cashoutStatus != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: cashoutStatus.$2.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(cashoutStatus.$1,
                      style: TextStyle(color: cashoutStatus.$2, fontSize: 10.5, fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
        ),
        Text(
          '${isCredit ? '+' : ''}${amount.toStringAsFixed(0)} FCFA',
          style: ClientText.bodyStrong.copyWith(color: color),
        ),
      ]),
    );
  }
}

class _WalletActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _WalletActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: disabled ? AppColors.lightIconMuted : AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                    color: disabled ? AppColors.lightIconMuted : AppColors.textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Feuille de retrait — montant, opérateur, bénéficiaire optionnel + OTP ────
class _CashoutSheet extends StatefulWidget {
  final WalletRepository repo;
  final double withdrawableBalance;
  const _CashoutSheet({required this.repo, required this.withdrawableBalance});

  @override
  State<_CashoutSheet> createState() => _CashoutSheetState();
}

class _CashoutSheetState extends State<_CashoutSheet> {
  final _amountCtrl    = TextEditingController();
  final _destPhoneCtrl = TextEditingController();
  final _destNameCtrl  = TextEditingController();
  final _otpCtrl       = TextEditingController();

  String _operator = 'WAVE';
  bool _thirdParty = false;
  bool _otpSent = false;
  bool _sendingOtp = false;
  bool _submitting = false;
  Key _swipeKey = UniqueKey();

  @override
  void dispose() {
    _amountCtrl.dispose();
    _destPhoneCtrl.dispose();
    _destNameCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final phone = _destPhoneCtrl.text.trim();
    if (phone.isEmpty) {
      showDemToast(context, 'Entrez le numéro du bénéficiaire.', isError: true);
      return;
    }
    setState(() => _sendingOtp = true);
    try {
      final result = await widget.repo.requestCashoutOtp(phone);
      if (!mounted) return;
      setState(() => _otpSent = true);
      if (result['sent'] == true) {
        showDemToast(context, 'Code envoyé par SMS à votre numéro.');
      }
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _submit() async {
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      showDemToast(context, 'Montant invalide.', isError: true);
      setState(() => _swipeKey = UniqueKey());
      return;
    }
    if (_thirdParty && (_destNameCtrl.text.trim().isEmpty || _destPhoneCtrl.text.trim().isEmpty)) {
      showDemToast(context, 'Nom et numéro du bénéficiaire requis.', isError: true);
      setState(() => _swipeKey = UniqueKey());
      return;
    }
    setState(() => _submitting = true);
    try {
      final result = await widget.repo.requestCashout(
        amount: amount,
        operatorName: _operator,
        destinationPhone: _thirdParty ? _destPhoneCtrl.text.trim() : null,
        destinationName: _thirdParty ? _destNameCtrl.text.trim() : null,
        otp: _thirdParty ? _otpCtrl.text.trim() : null,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        showDemToast(context, 'Retrait effectué !');
      } else {
        // Cas 202 : panne réseau pendant le virement SamirPay, vérification
        // manuelle en cours côté DEM (voir samirpay.service.js). Le solde a
        // déjà été débité — Dio traite 202 comme un succès générique (aucune
        // DioException), donc sans ce cas le driver ne voyait rien du tout.
        showDemToast(
          context,
          result['message'] as String? ?? 'Retrait en cours de vérification.',
          isError: false,
        );
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _swipeKey = UniqueKey());
        showDemToast(context, friendlyError(e), isError: true);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.70)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white, width: 1.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return GradientSheet(
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottom + 28),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Retirer vers Wave / Orange Money',
                style: ClientText.subtitle.copyWith(color: Colors.white)),
            const SizedBox(height: 4),
            Text('Solde retirable : ${widget.withdrawableBalance.toStringAsFixed(0)} FCFA',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.60), fontSize: 12)),
            const SizedBox(height: 20),
            TextField(
              controller: _amountCtrl,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _decoration('Montant (FCFA)'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _OperatorChip(
                  operatorName: 'WAVE',
                  selected: _operator == 'WAVE',
                  onTap: () => setState(() => _operator = 'WAVE'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _OperatorChip(
                  operatorName: 'ORANGE_MONEY',
                  selected: _operator == 'ORANGE_MONEY',
                  onTap: () => setState(() => _operator = 'ORANGE_MONEY'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Retirer vers un autre numéro',
                  style: ClientText.body.copyWith(color: Colors.white)),
              value: _thirdParty,
              onChanged: (v) => setState(() {
                _thirdParty = v;
                _otpSent = false;
              }),
              activeThumbColor: Colors.white,
              activeTrackColor: AppColors.primary,
            ),
            if (_thirdParty) ...[
              const SizedBox(height: 4),
              TextField(
                controller: _destNameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _decoration('Nom du bénéficiaire'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _destPhoneCtrl,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.phone,
                decoration: _decoration('Numéro du bénéficiaire'),
              ),
              const SizedBox(height: 10),
              if (!_otpSent)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _sendingOtp ? null : _sendOtp,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.40)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _sendingOtp
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Envoyer le code de confirmation', style: TextStyle(color: Colors.white)),
                  ),
                )
              else
                TextField(
                  controller: _otpCtrl,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _decoration('Code reçu par SMS'),
                ),
            ],
            const SizedBox(height: 24),
            SwipeToConfirm(
              key: _swipeKey,
              label: 'Glissez pour confirmer le retrait',
              onConfirmed: _submit,
              loading: _submitting,
              trackColor: AppColors.primary,
              thumbColor: Colors.white,
              iconColor: AppColors.primary,
              labelColor: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}

class _OperatorChip extends StatelessWidget {
  final String operatorName;
  final bool selected;
  final VoidCallback onTap;
  const _OperatorChip({required this.operatorName, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brandColor = PaymentOperatorBadge.colorFor(operatorName);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? brandColor.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? brandColor : Colors.white.withValues(alpha: 0.25),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PaymentOperatorBadge(operatorName: operatorName, size: 22),
            const SizedBox(width: 8),
            Text(PaymentOperatorBadge.labelFor(operatorName),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                )),
          ],
        ),
      ),
    );
  }
}
