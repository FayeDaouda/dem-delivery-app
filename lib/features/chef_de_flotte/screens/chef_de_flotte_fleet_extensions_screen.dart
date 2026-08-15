import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/network_error_widget.dart';
import '../../../shared/widgets/staggered_entrance.dart';
import '../data/chef_de_flotte_repository.dart';

/// Historique des demandes d'extension de flotte — jusqu'ici le chef de
/// flotte pouvait envoyer une demande (dialogue sur le Dashboard) mais ne
/// voyait jamais si elle avait été validée ou refusée. Devient aussi le
/// point d'entrée pour une nouvelle demande (remplace l'AlertDialog basique).
class ChefDeFlotteFleetExtensionsScreen extends StatefulWidget {
  const ChefDeFlotteFleetExtensionsScreen({super.key});
  @override
  State<ChefDeFlotteFleetExtensionsScreen> createState() => _State();
}

class _State extends State<ChefDeFlotteFleetExtensionsScreen> {
  final _repo = ChefDeFlotteRepository(ApiClient.dio);
  List<Map<String, dynamic>> _requests = [];
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
      final list = await _repo.getMyFleetExtensions();
      if (mounted) {
        setState(() {
          _requests = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  Future<void> _newRequest() async {
    final sizeCtrl = TextEditingController();
    final justCtrl = TextEditingController();
    bool submitting = false;

    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Container(
          decoration: const BoxDecoration(
            gradient: AppColors.gradientSplash,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(sheetCtx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 3,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Demander une extension',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Précisez la nouvelle taille souhaitée et la raison — un admin DEM validera votre demande.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: sizeCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: _sheetFieldDecoration('Nombre de motos demandé'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: justCtrl,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: _sheetFieldDecoration('Justification'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primaryMid,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: submitting
                      ? null
                      : () async {
                          final size = int.tryParse(sizeCtrl.text.trim());
                          if (size == null || justCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(sheetCtx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Renseignez une taille valide et une justification.',
                                ),
                              ),
                            );
                            return;
                          }
                          setSheetState(() => submitting = true);
                          try {
                            await _repo.requestFleetExtension(
                              requestedSize: size,
                              justification: justCtrl.text.trim(),
                            );
                            if (sheetCtx.mounted) Navigator.pop(sheetCtx, true);
                          } catch (e) {
                            setSheetState(() => submitting = false);
                            if (sheetCtx.mounted) {
                              ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                SnackBar(content: Text(friendlyError(e))),
                              );
                            }
                          }
                        },
                  child: submitting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primaryMid,
                          ),
                        )
                      : const Text('Envoyer la demande'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Demande envoyée !')));
      _load();
    }
  }

  InputDecoration _sheetFieldDecoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.white, width: 1.5),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 20),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        'Extensions de flotte',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _newRequest,
                      tooltip: 'Nouvelle demande',
                      icon: const Icon(
                        Icons.add_circle_outline,
                        color: Colors.white,
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
                    child: CircularProgressIndicator(
                      color: AppColors.primaryMid,
                    ),
                  )
                : _error != null
                ? NetworkErrorWidget(message: _error!, onRetry: _load)
                : _requests.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.expand_circle_down_outlined,
                            color: Colors.grey,
                            size: 44,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Aucune demande d\'extension',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Envoyez une demande si votre flotte a atteint sa limite actuelle.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Nouvelle demande'),
                            onPressed: _newRequest,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryMid,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    color: AppColors.primaryMid,
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      itemCount: _requests.length,
                      itemBuilder: (ctx, i) {
                        final r = _requests[i];
                        final status = r['status'] as String? ?? 'PENDING';
                        final createdAt = DateTime.tryParse(
                          r['createdAt'] as String? ?? '',
                        );
                        final updatedAt = DateTime.tryParse(
                          r['updatedAt'] as String? ?? '',
                        );
                        // updatedAt ne bouge que si l'admin a touché la
                        // demande (statut/notes) — s'il est toujours égal à
                        // createdAt, la décision n'est pas encore tombée.
                        final decidedAt =
                            (status != 'PENDING' &&
                                updatedAt != null &&
                                createdAt != null &&
                                updatedAt.isAfter(createdAt))
                            ? updatedAt
                            : null;
                        return StaggeredEntrance(
                          index: i,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.directions_bike,
                                      size: 16,
                                      color: AppColors.primaryMid,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${r['requestedSize']} motos',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  r['justification'] as String? ?? '',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black87,
                                  ),
                                ),
                                if ((r['adminNotes'] as String?)?.isNotEmpty ==
                                    true) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Réponse admin : ${r['adminNotes']}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                _RequestTimeline(
                                  status: status,
                                  createdAt: createdAt,
                                  decidedAt: decidedAt,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Mini-timeline "Envoyée → En revue → Décision" — un badge de statut ponctuel
/// ne dit rien du parcours de la demande ; ces 3 jalons donnent une sensation
/// de suivi sans champ backend supplémentaire (la 3ᵉ date vient de `updatedAt`,
/// qui ne bouge que quand l'admin tranche).
class _RequestTimeline extends StatelessWidget {
  final String status;
  final DateTime? createdAt;
  final DateTime? decidedAt;
  const _RequestTimeline({
    required this.status,
    this.createdAt,
    this.decidedAt,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = status != 'PENDING';
    final isApproved = status == 'APPROVED';
    final decisionColor = !resolved
        ? Colors.grey.shade300
        : (isApproved ? Colors.green : Colors.red);
    const activeColor = AppColors.primaryMid;

    Widget dot(Color color) => Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
    Widget line(Color color) =>
        Expanded(child: Container(height: 2, color: color));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            dot(activeColor),
            line(activeColor),
            dot(activeColor),
            line(resolved ? decisionColor : Colors.grey.shade300),
            dot(resolved ? decisionColor : Colors.grey.shade300),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                createdAt != null
                    ? 'Envoyée\n${_fmtDate(createdAt!)}'
                    : 'Envoyée',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
            Expanded(
              child: Text(
                'En revue',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: !resolved ? activeColor : Colors.grey,
                  fontWeight: !resolved ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Text(
                resolved
                    ? '${isApproved ? 'Validée' : 'Refusée'}${decidedAt != null ? '\n${_fmtDate(decidedAt!)}' : ''}'
                    : 'Décision',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 10,
                  color: resolved ? decisionColor : Colors.grey,
                  fontWeight: resolved ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
