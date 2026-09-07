import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/network_error_widget.dart';
import '../../../shared/widgets/staggered_entrance.dart';
import '../data/chef_de_flotte_repository.dart';
import '../utils/format.dart';
import '../widgets/driver_doc_picker_field.dart';

const Map<String, String> _kDocLabels = {
  'idCardFront': 'CNI — recto',
  'idCardBack': 'CNI — verso',
  'licenseFront': 'Permis — recto',
  'licenseBack': 'Permis — verso',
  'vehiclePhoto': 'Photo véhicule',
  'carteGrise': 'Carte grise — recto',
  'carteGriseBack': 'Carte grise — verso',
  'assurance': 'Attestation assurance',
  'casquePhoto': 'Photo casque',
};

const List<(String, String)> _kPeriods = [
  ('today', 'Jour'),
  ('week', 'Semaine'),
  ('month', 'Mois'),
  ('sixMonths', '6 mois'),
];

class ChefDeFlotteDriverDetailScreen extends StatefulWidget {
  final String driverId;
  const ChefDeFlotteDriverDetailScreen({super.key, required this.driverId});

  @override
  State<ChefDeFlotteDriverDetailScreen> createState() => _State();
}

class _State extends State<ChefDeFlotteDriverDetailScreen> {
  final _repo = ChefDeFlotteRepository(ApiClient.dio);

  Map<String, dynamic>? _driver;
  bool _loading = true;
  String? _error;
  bool _actionLoading = false;
  String _period = 'today';

  final Map<String, File> _pendingDocs = {};
  DateTime? _pendingInsuranceExpiry;

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
      final d = await _repo.getDriverDetail(widget.driverId);
      if (!mounted) return;
      setState(() {
        _driver = d;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  Color get _statusColor {
    final s = _driver?['chefDeFlotteStatus'] as String? ?? '';
    final active = _driver?['isActive'] as bool? ?? false;
    if (s == 'ACTIVE' && active) return Colors.green;
    if (s == 'ACTIVE' && !active) return Colors.grey;
    if (s == 'PENDING') return Colors.orange;
    if (s == 'REJECTED') return Colors.red;
    return Colors.grey;
  }

  String get _statusLabel {
    final s = _driver?['chefDeFlotteStatus'] as String? ?? '';
    final active = _driver?['isActive'] as bool? ?? false;
    if (s == 'ACTIVE' && active) return 'Actif';
    if (s == 'ACTIVE' && !active) return 'Suspendu';
    if (s == 'PENDING') return 'En attente';
    if (s == 'REJECTED') return 'Refusé';
    return '—';
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _driver?['name'] as String? ?? '');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
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
              'Modifier le nom',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.white,
              decoration: InputDecoration(
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
                  borderSide: const BorderSide(color: Colors.white, width: 1.5),
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
                onPressed: () => Navigator.pop(sheetCtx, true),
                child: const Text('Enregistrer'),
              ),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final name = ctrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _actionLoading = true);
    try {
      await _repo.updateDriver(widget.driverId, name: name);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _saveDocuments() async {
    if (_pendingDocs.isEmpty && _pendingInsuranceExpiry == null) return;
    setState(() => _actionLoading = true);
    try {
      await _repo.uploadDriverDocuments(
        widget.driverId,
        files: _pendingDocs,
        insuranceExpiry: _pendingInsuranceExpiry,
      );
      _pendingDocs.clear();
      _pendingInsuranceExpiry = null;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Documents mis à jour.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _suspend() async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Padding(
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
              'Suspendre ce livreur ?',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 6),
            const Text(
              'Il ne pourra plus recevoir de courses tant qu\'il n\'est pas réactivé.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reasonCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Motif (optionnel)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetCtx, false),
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(sheetCtx, true),
                    child: const Text('Suspendre'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _actionLoading = true);
    try {
      await _repo.suspendDriver(widget.driverId, reason: reasonCtrl.text);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _activate() async {
    setState(() => _actionLoading = true);
    try {
      await _repo.activateDriver(widget.driverId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _resubmit() async {
    setState(() => _actionLoading = true);
    try {
      await _repo.resubmitDriver(widget.driverId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dossier resoumis pour validation.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryMid),
            )
          : _error != null
          ? NetworkErrorWidget(message: _error!, onRetry: _load)
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final d = _driver!;
    final name = (d['name'] as String?)?.trim();
    final hasName = name?.isNotEmpty == true;
    final phone = d['phone'] as String? ?? '';
    final status = d['chefDeFlotteStatus'] as String? ?? '';
    final rejectionReason = d['rejectionReason'] as String?;
    final suspensionReason = d['suspensionReason'] as String?;
    final avgRating = (d['avgRating'] as num?)?.toDouble();
    final statsByPeriod = (d['statsByPeriod'] as Map?) ?? {};
    final periodStats =
        statsByPeriod[_period] as Map? ?? {'courses': 0, 'earnings': 0};

    final insuranceDate =
        _pendingInsuranceExpiry ??
        (d['insuranceExpiry'] != null
            ? DateTime.tryParse(d['insuranceExpiry'] as String)
            : null);
    final insuranceDaysLeft = insuranceDate?.difference(DateTime.now()).inDays;
    final insuranceExpired = insuranceDaysLeft != null && insuranceDaysLeft < 0;
    final insuranceExpiringSoon =
        insuranceDaysLeft != null &&
        insuranceDaysLeft >= 0 &&
        insuranceDaysLeft <= 30;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 210,
          pinned: true,
          backgroundColor: AppColors.primaryDark,
          foregroundColor: Colors.white,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: AppColors.gradientSplash,
              ),
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white.withValues(alpha: 0.20),
                    child: Text(
                      hasName ? name![0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          hasName ? name! : phone,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: Colors.white70,
                          size: 18,
                        ),
                        onPressed: _actionLoading ? null : _editName,
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.only(left: 8),
                      ),
                    ],
                  ),
                  Text(
                    phone,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: _statusColor == Colors.grey
                                ? Colors.white70
                                : _statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _statusLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
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

        // ── Stats ──────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: StaggeredEntrance(
            index: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      _StatCard(
                        label: 'Livrées',
                        value: '${d['deliveredCourses'] ?? 0}',
                        icon: Icons.check_circle_outline,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 10),
                      _StatCard(
                        label: 'En cours',
                        value: '${d['pendingCourses'] ?? 0}',
                        icon: Icons.local_shipping_outlined,
                        color: AppColors.primaryMid,
                      ),
                      const SizedBox(width: 10),
                      _StatCard(
                        label: 'Note',
                        value: avgRating != null
                            ? avgRating.toStringAsFixed(1)
                            : '—',
                        icon: Icons.star_rounded,
                        color: Colors.amber.shade700,
                      ),
                      const SizedBox(width: 10),
                      _StatCard(
                        label: 'Actif aujourd\'hui',
                        value: formatActiveDuration(
                          (d['activeSecondsToday'] as num?)?.toInt() ?? 0,
                        ),
                        icon: Icons.timer_outlined,
                        color: Colors.blueGrey,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            for (final p in _kPeriods)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(
                                    p.$2,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: _period == p.$1
                                          ? Colors.white
                                          : AppColors.primaryMid,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  selected: _period == p.$1,
                                  onSelected: (_) =>
                                      setState(() => _period = p.$1),
                                  selectedColor: AppColors.primaryMid,
                                  backgroundColor: const Color(0xFFF1F5F9),
                                  showCheckmark: false,
                                  elevation: 0,
                                  pressElevation: 0,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${periodStats['courses'] ?? 0} course${(periodStats['courses'] ?? 0) > 1 ? 's' : ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${((periodStats['earnings'] as num?) ?? 0).round()} FCFA',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primaryMid,
                                  ),
                                ),
                                if (((periodStats['demFee'] as num?) ?? 0) > 0)
                                  Text(
                                    // Frais DEM déjà déduits de "earnings".
                                    '(dont ${((periodStats['demFee'] as num).round())} FCFA de frais DEM)',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Bandeau refus / suspension ────────────────────────────────────
        if (status == 'REJECTED' && rejectionReason != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _InfoBanner(
                icon: Icons.cancel_outlined,
                color: Colors.red,
                title: 'Dossier refusé',
                message: rejectionReason,
              ),
            ),
          ),
        if (status == 'ACTIVE' &&
            d['isActive'] == false &&
            suspensionReason != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _InfoBanner(
                icon: Icons.pause_circle_outline,
                color: Colors.grey.shade700,
                title: 'Livreur suspendu',
                message: suspensionReason,
              ),
            ),
          ),

        // ── Documents ─────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: StaggeredEntrance(
            index: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Documents',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  ...(_kDocLabels.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DriverDocPickerField(
                        label: e.value,
                        existingUrl: d[e.key] as String?,
                        onChanged: (file) => setState(() {
                          if (file != null) {
                            _pendingDocs[e.key] = file;
                          } else {
                            _pendingDocs.remove(e.key);
                          }
                        }),
                      ),
                    ),
                  )),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Expiration assurance',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      if (insuranceExpired || insuranceExpiringSoon) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color:
                                (insuranceExpired ? Colors.red : Colors.orange)
                                    .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            insuranceExpired
                                ? 'Expirée'
                                : 'Expire dans $insuranceDaysLeft j',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: insuranceExpired
                                  ? Colors.red.shade700
                                  : Colors.orange.shade800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate:
                            _pendingInsuranceExpiry ??
                            (d['insuranceExpiry'] != null
                                ? DateTime.tryParse(
                                        d['insuranceExpiry'] as String,
                                      ) ??
                                      DateTime.now()
                                : DateTime.now()),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(
                          const Duration(days: 365 * 3),
                        ),
                      );
                      if (picked != null) {
                        setState(() => _pendingInsuranceExpiry = picked);
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: insuranceExpired
                            ? Colors.red.withValues(alpha: 0.06)
                            : insuranceExpiringSoon
                            ? Colors.orange.withValues(alpha: 0.08)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: insuranceExpired
                              ? Colors.red.shade200
                              : insuranceExpiringSoon
                              ? Colors.orange.shade200
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            insuranceExpired || insuranceExpiringSoon
                                ? Icons.warning_amber_rounded
                                : Icons.event_outlined,
                            color: insuranceExpired
                                ? Colors.red.shade400
                                : insuranceExpiringSoon
                                ? Colors.orange.shade400
                                : const Color(0xFF9CA3AF),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            insuranceDate != null
                                ? _fmtDate(insuranceDate)
                                : 'Non renseignée',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF374151),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_pendingDocs.isNotEmpty ||
                      _pendingInsuranceExpiry != null)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _actionLoading ? null : _saveDocuments,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryMid,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _actionLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Enregistrer les documents'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        // ── Actions statut ───────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: Column(
              children: [
                if (status == 'REJECTED')
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _actionLoading ? null : _resubmit,
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('Resoumettre mon dossier'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryMid,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                if (status == 'ACTIVE' && d['isActive'] == true)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _actionLoading ? null : _suspend,
                      icon: const Icon(Icons.pause_circle_outline),
                      label: const Text('Suspendre ce livreur'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                if (status == 'ACTIVE' && d['isActive'] == false)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _actionLoading ? null : _activate,
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Réactiver ce livreur'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                if (status == 'PENDING')
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.hourglass_top_rounded,
                          color: Colors.orange.shade700,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'En attente de validation par l\'équipe DEM.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange,
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
      ],
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    ),
  );
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w700, color: color),
              ),
              const SizedBox(height: 2),
              Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  color: color.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
