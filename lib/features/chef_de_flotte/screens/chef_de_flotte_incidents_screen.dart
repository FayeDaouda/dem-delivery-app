import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/network_error_widget.dart';
import '../../../shared/widgets/pressable.dart';
import '../../../shared/widgets/staggered_entrance.dart';
import '../data/chef_de_flotte_repository.dart';

const Map<String, String> _kStatusLabels = {
  'OPEN': 'Ouvert',
  'INVESTIGATING': 'En cours',
  'RESOLVED': 'Résolu',
};

const Map<String, Color> _kSeverityColors = {
  'low': Colors.blueGrey,
  'medium': Colors.orange,
  'high': Colors.deepOrange,
  'critical': Colors.red,
};

/// Incidents de la flotte — fusionne les incidents réels (signalements,
/// livreur injoignable...) et deux types d'alertes synthétiques générées à
/// la volée côté serveur, jamais modifiables (purement informatives) :
/// livreur inactif depuis 72h (id préfixé `inactive-`) et assurance qui
/// expire (id préfixé `insurance-`, ouvre directement le livreur concerné
/// — plus actionnable qu'un simple message).
class ChefDeFlotteIncidentsScreen extends StatefulWidget {
  const ChefDeFlotteIncidentsScreen({super.key});
  @override
  State<ChefDeFlotteIncidentsScreen> createState() => _State();
}

class _State extends State<ChefDeFlotteIncidentsScreen> {
  final _repo = ChefDeFlotteRepository(ApiClient.dio);
  List<Map<String, dynamic>> _incidents = [];
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
      final list = await _repo.getMyIncidents();
      if (mounted) {
        setState(() {
          _incidents = list;
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

  Future<void> _openIncident(Map<String, dynamic> incident) async {
    final id = incident['id'] as String;
    if (id.startsWith('insurance-')) {
      final driverId = incident['driverId'] as String?;
      if (driverId != null) context.push('/chef-de-flotte/drivers/$driverId');
      return;
    }
    if (id.startsWith('inactive-')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Alerte automatique — contactez directement ce livreur.',
          ),
        ),
      );
      return;
    }

    var status = incident['status'] as String? ?? 'OPEN';
    final notesCtrl = TextEditingController(
      text: incident['notes'] as String? ?? '',
    );
    bool submitting = false;

    final saved = await showModalBottomSheet<bool>(
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
              Text(
                incident['label'] as String? ?? 'Incident',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Statut',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in _kStatusLabels.keys)
                    ChoiceChip(
                      label: Text(_kStatusLabels[s]!),
                      selected: status == s,
                      onSelected: (_) => setSheetState(() => status = s),
                      selectedColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.14),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                      labelStyle: TextStyle(
                        color: status == s
                            ? AppColors.primaryMid
                            : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      showCheckmark: false,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: notesCtrl,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  labelText: 'Notes (optionnel)',
                  labelStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Colors.white,
                      width: 1.5,
                    ),
                  ),
                ),
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
                          setSheetState(() => submitting = true);
                          try {
                            await _repo.updateMyIncident(
                              id,
                              status: status,
                              notes: notesCtrl.text.trim(),
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
                      : const Text('Enregistrer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == true) _load();
  }

  String _relativeTime(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
    return 'il y a ${diff.inDays} j';
  }

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
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 20),
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
                    const Text(
                      'Incidents',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
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
                : _incidents.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: Colors.green.shade400,
                            size: 44,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Aucun incident',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Votre flotte ne signale rien d\'anormal pour le moment.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 13),
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
                      itemCount: _incidents.length,
                      itemBuilder: (ctx, i) {
                        final inc = _incidents[i];
                        final incId = inc['id'] as String;
                        final isSynthetic =
                            incId.startsWith('inactive-') ||
                            incId.startsWith('insurance-');
                        final severity = inc['severity'] as String? ?? 'low';
                        final status = inc['status'] as String? ?? 'OPEN';
                        final severityColor =
                            _kSeverityColors[severity] ?? Colors.grey;
                        final openedAt = DateTime.tryParse(
                          inc['openedAt'] as String? ?? '',
                        );
                        final driverName = inc['driverName'] as String?;
                        final driverPhone = inc['driverPhone'] as String?;

                        return StaggeredEntrance(
                          index: i,
                          child: Opacity(
                            opacity: status == 'RESOLVED' ? 0.6 : 1,
                            child: Pressable(
                              onTap: () => _openIncident(inc),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border(
                                    left: BorderSide(
                                      color: severityColor,
                                      width: 3,
                                    ),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.04,
                                      ),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            inc['label'] as String? ?? '—',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        if (!isSynthetic)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  (status == 'RESOLVED'
                                                          ? Colors.green
                                                          : AppColors
                                                                .primaryMid)
                                                      .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              _kStatusLabels[status] ?? status,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: status == 'RESOLVED'
                                                    ? Colors.green.shade700
                                                    : AppColors.primaryMid,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (driverName != null ||
                                        driverPhone != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        [
                                          driverName,
                                          driverPhone,
                                        ].whereType<String>().join(' · '),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                    if (openedAt != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        _relativeTime(openedAt),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
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
