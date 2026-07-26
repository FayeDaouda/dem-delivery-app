import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../data/dem_pro_repository.dart';
import '../theme/dem_pro_colors.dart';
import '../theme/dem_pro_text.dart';

String _timeAgo(String? iso) {
  if (iso == null) return '';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1)  return 'À l\'instant';
  if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
  if (diff.inHours < 24)   return 'Il y a ${diff.inHours} h';
  return 'Il y a ${diff.inDays} j';
}

String _statusLabel(String s) => switch (s) {
  'CONFIRMED' => 'Confirmée',
  'REJECTED'  => 'Rejetée',
  _           => 'En attente',
};

Color _statusColor(String s) => switch (s) {
  'CONFIRMED' => DemProColors.success,
  'REJECTED'  => DemProColors.danger,
  _           => DemProColors.warning,
};

/// Demandes de livraison soumises par des clients finaux (sans compte DEM)
/// via le lien de commande public — le commerçant confirme (crée la vraie
/// commande, en positionnant lui-même le point de livraison) ou rejette.
class DemProOrderRequestsScreen extends StatefulWidget {
  const DemProOrderRequestsScreen({super.key});
  @override
  State<DemProOrderRequestsScreen> createState() => _DemProOrderRequestsScreenState();
}

class _DemProOrderRequestsScreenState extends State<DemProOrderRequestsScreen> {
  final _repo = DemProRepository(ApiClient.dio);

  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _loadFailed = false; });
    try {
      final requests = await _repo.getOrderRequests();
      if (!mounted) return;
      setState(() { _requests = requests; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _loadFailed = true; });
    }
  }

  Future<void> _confirm(Map<String, dynamic> request) async {
    await context.push('/dem-pro/orders/create', extra: {'fromOrderRequest': request});
    if (mounted) _load();
  }

  Future<void> _reject(Map<String, dynamic> request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: DemProColors.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Rejeter cette demande ?', style: DemProText.title.copyWith(color: DemProColors.text, fontSize: 17)),
        content: Text(
          '${request['customerName']} ne sera pas notifié — vous pourrez lui répondre directement si besoin.',
          style: DemProText.body.copyWith(color: DemProColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Annuler', style: DemProText.body.copyWith(color: DemProColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Rejeter', style: DemProText.body.copyWith(color: DemProColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.rejectOrderRequest(request['id'] as String);
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
    final pending = _requests.where((r) => r['status'] == 'PENDING').toList();
    final processed = _requests.where((r) => r['status'] != 'PENDING').toList();

    return Scaffold(
      backgroundColor: DemProColors.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
            child: Row(children: [
              IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back_ios_new, color: DemProColors.text, size: 18),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Demandes reçues', style: DemProText.headline.copyWith(color: DemProColors.text, fontSize: 20)),
                  Text('Via votre lien de commande', style: DemProText.caption.copyWith(color: DemProColors.muted)),
                ]),
              ),
              if (pending.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: DemProColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${pending.length}', style: DemProText.caption.copyWith(color: DemProColors.warning, fontWeight: FontWeight.w800)),
                ),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: DemProColors.accent))
                : _loadFailed
                    ? _buildError()
                    : (pending.isEmpty && processed.isEmpty)
                        ? _buildEmpty()
                        : RefreshIndicator(
                            color: DemProColors.accent,
                            backgroundColor: DemProColors.bg2,
                            onRefresh: _load,
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                              children: [
                                if (pending.isNotEmpty) ...[
                                  _SectionLabel('EN ATTENTE'),
                                  const SizedBox(height: 10),
                                  ...pending.map((r) => _RequestCard(
                                    request: r,
                                    onConfirm: () => _confirm(r),
                                    onReject: () => _reject(r),
                                  )),
                                  const SizedBox(height: 20),
                                ],
                                if (processed.isNotEmpty) ...[
                                  _SectionLabel('TRAITÉES'),
                                  const SizedBox(height: 10),
                                  ...processed.map((r) => _RequestCard(request: r)),
                                ],
                              ],
                            ),
                          ),
          ),
        ]),
      ),
    );
  }

  Widget _buildEmpty() => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.symmetric(horizontal: 32),
    children: [
      const SizedBox(height: 70),
      Container(
        width: 80, height: 80,
        decoration: BoxDecoration(color: DemProColors.accent.withValues(alpha: 0.10), shape: BoxShape.circle),
        child: const Icon(Icons.link_rounded, color: DemProColors.accent, size: 36),
      ),
      const SizedBox(height: 20),
      Text('Aucune demande pour l\'instant', style: DemProText.title.copyWith(color: DemProColors.text, fontSize: 17), textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(
        'Partagez votre lien de commande depuis l\'accueil pour que vos clients puissent commander directement.',
        style: DemProText.body.copyWith(color: DemProColors.muted, height: 1.5),
        textAlign: TextAlign.center,
      ),
    ],
  );

  Widget _buildError() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.wifi_off_rounded, color: DemProColors.muted, size: 36),
      const SizedBox(height: 12),
      Text('Impossible de charger les demandes', style: DemProText.subtitle.copyWith(color: DemProColors.text, fontSize: 15)),
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

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) => Text(
    label,
    style: DemProText.caption.copyWith(color: DemProColors.muted, fontWeight: FontWeight.w700, letterSpacing: 1),
  );
}

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback? onConfirm;
  final VoidCallback? onReject;
  const _RequestCard({required this.request, this.onConfirm, this.onReject});

  @override
  Widget build(BuildContext context) {
    final status = request['status'] as String? ?? 'PENDING';
    final name = request['customerName'] as String? ?? '—';
    final phone = request['customerPhone'] as String?;
    final address = request['deliveryAddress'] as String? ?? '';
    final landmark = request['landmark'] as String?;
    final notes = request['notes'] as String?;
    final isPending = status == 'PENDING';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DemProColors.bg2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isPending ? DemProColors.warning.withValues(alpha: 0.3) : DemProColors.bg3),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: DemProColors.accent.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: const Icon(Icons.person_outline, color: DemProColors.accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: DemProText.subtitle.copyWith(color: DemProColors.text), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(_timeAgo(request['createdAt'] as String?), style: DemProText.caption.copyWith(color: DemProColors.muted)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Text(_statusLabel(status), style: DemProText.caption.copyWith(color: _statusColor(status), fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.location_on_outlined, color: DemProColors.muted, size: 15),
          const SizedBox(width: 8),
          Expanded(child: Text(address, style: DemProText.body.copyWith(color: DemProColors.text))),
        ]),
        if (landmark != null && landmark.isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 23),
            child: Text(landmark, style: DemProText.caption.copyWith(color: DemProColors.muted)),
          ),
        ],
        if (notes != null && notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: DemProColors.bg3, borderRadius: BorderRadius.circular(10)),
            child: Text(notes, style: DemProText.caption.copyWith(color: DemProColors.text)),
          ),
        ],
        if (phone != null && phone.isNotEmpty) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => launchUrl(Uri.parse('tel:$phone')),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.phone_outlined, color: DemProColors.accent, size: 14),
              const SizedBox(width: 6),
              Text(phone, style: DemProText.caption.copyWith(color: DemProColors.accent, fontWeight: FontWeight.w700)),
            ]),
          ),
        ],
        if (isPending) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onReject,
                style: OutlinedButton.styleFrom(
                  foregroundColor: DemProColors.danger,
                  side: BorderSide(color: DemProColors.danger.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Rejeter', style: DemProText.bodyStrong),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: DemProColors.accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Confirmer', style: DemProText.bodyStrong),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}
