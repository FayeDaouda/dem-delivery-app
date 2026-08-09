import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';
import '../../../core/utils/dem_toast.dart';
import '../../../core/utils/price_format.dart';
import '../data/dem_pro_repository.dart';

String _txLabel(String type) => switch (type) {
  'CREDIT_PRO_SALE' => 'Vente',
  'DEBIT_CASHOUT' => 'Retrait',
  'CREDIT_TOPUP' => 'Recharge',
  'CREDIT_PROMO_SUBSIDY' => 'Remboursement promo',
  _ => type,
};

class DemProWalletScreen extends StatefulWidget {
  const DemProWalletScreen({super.key});
  @override
  State<DemProWalletScreen> createState() => _DemProWalletScreenState();
}

class _DemProWalletScreenState extends State<DemProWalletScreen> {
  final _repo = DemProRepository(ApiClient.dio);

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _summary;

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
      final summary = await _repo.getWalletSummary();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AppException ? e.message : 'Erreur de chargement.';
        _loading = false;
      });
    }
  }

  Future<void> _showCashoutSheet() async {
    final withdrawable = (_summary?['withdrawableBalance'] as num?) ?? 0;
    if (withdrawable <= 0) {
      showDemToast(context, 'Aucun solde retirable pour le moment.');
      return;
    }
    final refreshed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CashoutSheet(repo: _repo, maxAmount: withdrawable.toInt()),
    );
    if (refreshed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final balance = (_summary?['balance'] as num?) ?? 0;
    final withdrawable = (_summary?['withdrawableBalance'] as num?) ?? 0;
    final transactions =
        (_summary?['recentTransactions'] as List?)?.cast<Map<String, dynamic>>() ??
        [];

    return Scaffold(
      backgroundColor: AppColors.lightBg,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => context.pop(),
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        Text(
                          'Wallet DEM Pro',
                          style: ClientText.title.copyWith(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Solde retirable',
                            style: ClientText.label.copyWith(
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _loading ? '···' : formatFcfa(withdrawable),
                            style: ClientText.hero.copyWith(
                              color: Colors.white,
                              fontSize: 34,
                            ),
                          ),
                          if (!_loading && balance != withdrawable) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Solde total (avant retrait) : ${formatFcfa(balance)}',
                              style: ClientText.micro.copyWith(
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          GestureDetector(
                            onTap: _loading ? null : _showCashoutSheet,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.account_balance_wallet_outlined,
                                    color: AppColors.primary,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Retirer vers Wave / Orange Money',
                                    style: ClientText.bodyStrong.copyWith(
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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
                        Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 36),
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: ClientText.body.copyWith(color: AppColors.textMuted),
                        ),
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: _load,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Réessayer',
                              style: ClientText.button.copyWith(fontSize: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: _load,
                    child: transactions.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: MediaQuery.of(context).size.height * 0.4,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.receipt_long_outlined,
                                        color: AppColors.textMuted,
                                        size: 36,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Aucune transaction pour le moment',
                                        style: ClientText.body.copyWith(
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                            itemCount: transactions.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, i) =>
                                _TransactionRow(tx: transactions[i]),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  final Map<String, dynamic> tx;
  const _TransactionRow({required this.tx});

  @override
  Widget build(BuildContext context) {
    final type = tx['type'] as String? ?? '';
    final amount = (tx['amount'] as num?) ?? 0;
    final isCredit = amount >= 0;
    final description = tx['description'] as String? ?? _txLabel(type);
    final createdAt = DateTime.tryParse(tx['createdAt'] as String? ?? '')?.toLocal();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: (isCredit ? AppColors.successLight : AppColors.error)
                  .withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              color: isCredit ? AppColors.successLight : AppColors.error,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: ClientText.bodyStrong.copyWith(color: AppColors.textDark),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (createdAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year} à ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                    style: ClientText.label.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : ''}${formatFcfa(amount)}',
            style: ClientText.bodyStrong.copyWith(
              color: isCredit ? AppColors.successLight : AppColors.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _CashoutSheet extends StatefulWidget {
  final DemProRepository repo;
  final int maxAmount;
  const _CashoutSheet({required this.repo, required this.maxAmount});

  @override
  State<_CashoutSheet> createState() => _CashoutSheetState();
}

class _CashoutSheetState extends State<_CashoutSheet> {
  final _amountCtrl = TextEditingController();
  String _operator = 'WAVE';
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Montant invalide.');
      return;
    }
    if (amount > widget.maxAmount) {
      setState(() => _error = 'Maximum retirable : ${formatFcfa(widget.maxAmount)}.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.repo.requestCashout(amount: amount, operatorName: _operator);
      if (mounted) Navigator.pop(context, true);
    } on AppException catch (e) {
      if (mounted) setState(() {
        _error = e.message;
        _submitting = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _error = 'Le retrait a échoué.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      20,
      16,
      20,
      MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).viewPadding.bottom + 24,
    ),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.lightBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Retirer mon solde',
            style: ClientText.title.copyWith(color: AppColors.textDark, fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(
            'Maximum retirable : ${formatFcfa(widget.maxAmount)}',
            style: ClientText.label.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 18),
          Text('Montant (FCFA)', style: ClientText.label.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 6),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            style: ClientText.body.copyWith(color: AppColors.textDark),
            decoration: InputDecoration(
              hintText: 'ex: 5000',
              filled: true,
              fillColor: AppColors.lightFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
          Text('Opérateur', style: ClientText.label.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _OperatorChip(
                  label: 'Wave',
                  active: _operator == 'WAVE',
                  onTap: () => setState(() => _operator = 'WAVE'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _OperatorChip(
                  label: 'Orange Money',
                  active: _operator == 'ORANGE_MONEY',
                  onTap: () => setState(() => _operator = 'ORANGE_MONEY'),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: ClientText.label.copyWith(color: AppColors.error)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Confirmer le retrait'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _OperatorChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _OperatorChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: active ? AppColors.primary : AppColors.lightFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? AppColors.primary : AppColors.lightBorder,
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: ClientText.bodyStrong.copyWith(
          color: active ? Colors.white : AppColors.textDark,
        ),
      ),
    ),
  );
}
