import 'package:flutter/material.dart';

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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => Padding(
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
              const Text(
                'Demander une extension',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
              const SizedBox(height: 6),
              const Text(
                'Précisez la nouvelle taille souhaitée et la raison — un admin DEM validera votre demande.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: sizeCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nombre de motos demandé',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: justCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Justification',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryMid,
                    foregroundColor: Colors.white,
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
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
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

  (Color, String) _statusInfo(String status) => switch (status) {
    'APPROVED' => (Colors.green, 'Validée'),
    'REJECTED' => (Colors.red, 'Refusée'),
    _ => (Colors.orange, 'En attente'),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        title: const Text('Extensions de flotte'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Nouvelle demande',
            onPressed: _newRequest,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryMid),
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
                  final (color, label) = _statusInfo(
                    r['status'] as String? ?? 'PENDING',
                  );
                  final createdAt = DateTime.tryParse(
                    r['createdAt'] as String? ?? '',
                  );
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
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
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
                          if (createdAt != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _fmtDate(createdAt),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
