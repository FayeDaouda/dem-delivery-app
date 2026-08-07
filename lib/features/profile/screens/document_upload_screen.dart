import 'dart:io';
import 'package:dio/dio.dart';
import '../../../core/error/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';
import '../../../core/utils/dem_toast.dart';


// Groupes de documents obligatoires (certains ont recto+verso)
class _DocGroup {
  final String title;
  final IconData icon;
  final List<_DocDef> slots;
  const _DocGroup({required this.title, required this.icon, required this.slots});
}

const _kDocs = [
  _DocDef(field: 'licenseFront',   label: 'Permis — Recto',      hint: 'Face avant du permis',       icon: Icons.credit_card_outlined),
  _DocDef(field: 'licenseBack',    label: 'Permis — Verso',       hint: 'Face arrière du permis',      icon: Icons.credit_card_outlined),
  _DocDef(field: 'carteGrise',     label: 'Carte grise — Recto',  hint: 'Face avant de la carte grise', icon: Icons.directions_car_outlined),
  _DocDef(field: 'carteGriseBack', label: 'Carte grise — Verso',  hint: 'Face arrière de la carte grise', icon: Icons.directions_car_outlined),
  _DocDef(field: 'assurance',      label: 'Assurance valide',     hint: 'Attestation en cours de validité', icon: Icons.security_outlined),
  _DocDef(field: 'vehiclePhoto',   label: 'Photo moto — plaque visible', hint: 'Plaque lisible sur la photo', icon: Icons.two_wheeler),
  _DocDef(field: 'avatar',         label: 'Photo profil',         hint: 'Votre visage bien visible',   icon: Icons.person_outline_rounded),
];

// Groupes visuels (recto+verso côte à côte)
final _kGroups = [
  _DocGroup(title: 'Permis de conduire',  icon: Icons.credit_card_outlined,
      slots: [_kDocs[0], _kDocs[1]]),
  _DocGroup(title: 'Carte grise',         icon: Icons.directions_car_outlined,
      slots: [_kDocs[2], _kDocs[3]]),
  _DocGroup(title: 'Assurance valide',    icon: Icons.security_outlined,
      slots: [_kDocs[4]]),
  _DocGroup(title: 'Photo moto — plaque visible', icon: Icons.two_wheeler,
      slots: [_kDocs[5]]),
  _DocGroup(title: 'Photo profil',        icon: Icons.person_outline_rounded,
      slots: [_kDocs[6]]),
];

class _DocDef {
  final String field;
  final String label;
  final String hint;
  final IconData icon;
  const _DocDef({required this.field, required this.label, required this.hint, required this.icon});
}

class DocumentUploadScreen extends StatefulWidget {
  const DocumentUploadScreen({super.key});

  @override
  State<DocumentUploadScreen> createState() => _DocumentUploadScreenState();
}

class _DocumentUploadScreenState extends State<DocumentUploadScreen> {
  final Map<String, File?>   _files     = { for (final d in _kDocs) d.field: null };
  final Map<String, String?> _urls      = { for (final d in _kDocs) d.field: null };
  final Map<String, bool>    _uploading = { for (final d in _kDocs) d.field: false };
  Map<String, Map<String, dynamic>> _rejections = {};
  bool _loadingExisting = true;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  // Charge les URLs déjà uploadées depuis le profil
  Future<void> _loadExisting() async {
    try {
      final res  = await ApiClient.dio.get('/users/me');
      final user = res.data as Map<String, dynamic>?;
      if (user != null && mounted) {
        setState(() {
          for (final d in _kDocs) {
            _urls[d.field] = user[d.field] as String?;
          }
          final rej = user['rejectedDocuments'] as Map<String, dynamic>?;
          _rejections = rej?.map(
                (k, v) => MapEntry(k, v as Map<String, dynamic>),
              ) ??
              {};
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingExisting = false);
  }

  Future<void> _pick(String field, ImageSource source) async {
    final xfile = await _picker.pickImage(source: source, imageQuality: 80);
    if (xfile == null) return;
    setState(() => _files[field] = File(xfile.path));
    await _upload(field);
  }

  Future<void> _upload(String field) async {
    final file = _files[field];
    if (file == null) return;
    setState(() => _uploading[field] = true);
    try {
      final form = FormData.fromMap({
        'field': field,
        'file':  await MultipartFile.fromFile(file.path, filename: '$field.jpg'),
      });
      final res  = await ApiClient.dio.post('/users/driver/documents', data: form);
      final user = res.data['user'] as Map<String, dynamic>?;
      if (user != null && mounted) {
        setState(() {
          _urls[field] = user[field] as String?;
          _rejections.remove(field);
        });
        showDemToast(context, 'Document enregistré ✓');
      }
    } catch (e) {
      if (mounted) showDemToast(context, friendlyError(e), isError: true);
    } finally {
      if (mounted) setState(() => _uploading[field] = false);
    }
  }

  void _showSourcePicker(String field) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          gradient: AppColors.gradientSplash,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewPadding.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _SourceBtn(
              icon: Icons.camera_alt_outlined,
              label: 'Prendre une photo',
              onTap: () { Navigator.pop(context); _pick(field, ImageSource.camera); },
            ),
            const SizedBox(height: 10),
            _SourceBtn(
              icon: Icons.photo_library_outlined,
              label: 'Choisir dans la galerie',
              onTap: () { Navigator.pop(context); _pick(field, ImageSource.gallery); },
            ),
          ],
        ),
      ),
    );
  }

  int get _uploadedCount => _urls.entries
      .where((e) => e.value != null && !_rejections.containsKey(e.key))
      .length;

  @override
  Widget build(BuildContext context) {
    final uploaded = _uploadedCount;
    final total    = _kDocs.length;
    final allDone  = uploaded == total;

    return Scaffold(
      backgroundColor: AppColors.lightBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ──
          Container(
            decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                        ),
                        const Spacer(),
                        Text('Documents',
                            style: ClientText.subtitle.copyWith(color: Colors.white)),
                        const Spacer(),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  // Barre de progression
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('$uploaded/$total documents',
                                style: ClientText.label.copyWith(color: Colors.white)),
                            const Spacer(),
                            if (allDone)
                              Text('✅ Profil complet',
                                  style: ClientText.labelStrong.copyWith(color: AppColors.successBright)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: total > 0 ? uploaded / total : 0,
                            minHeight: 5,
                            backgroundColor: Colors.white.withValues(alpha: 0.20),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              allDone ? AppColors.successBright : Colors.white,
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

          // ── Corps ──
          Expanded(
            child: _loadingExisting
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      // Bannière info
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: AppColors.primary, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Photos nettes et bien éclairées. JPG/PNG, max 5 Mo.',
                                style: TextStyle(color: AppColors.primary.withValues(alpha: 0.85), fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Groupes de documents
                      ...List.generate(_kGroups.length, (i) {
                        final group = _kGroups[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Titre du groupe
                              Row(children: [
                                Icon(group.icon, color: AppColors.primary, size: 15),
                                const SizedBox(width: 6),
                                Text(group.title,
                                    style: ClientText.labelStrong.copyWith(color: AppColors.textDark)),
                              ]),
                              const SizedBox(height: 8),
                              // Slots : 1 seul → pleine largeur, 2 → côte à côte
                              if (group.slots.length == 1)
                                _DocCard(
                                  doc:       group.slots[0],
                                  file:      _files[group.slots[0].field],
                                  url:       _urls[group.slots[0].field],
                                  uploading: _uploading[group.slots[0].field]!,
                                  rejection: _rejections[group.slots[0].field],
                                  onTap:     () => _showSourcePicker(group.slots[0].field),
                                )
                              else
                                Row(
                                  children: group.slots.map((doc) => Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        right: doc == group.slots.first ? 8 : 0,
                                      ),
                                      child: _DocCard(
                                        doc:       doc,
                                        file:      _files[doc.field],
                                        url:       _urls[doc.field],
                                        uploading: _uploading[doc.field]!,
                                        rejection: _rejections[doc.field],
                                        onTap:     () => _showSourcePicker(doc.field),
                                        compact:   true,
                                      ),
                                    ),
                                  )).toList(),
                                ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Carte document (1 par ligne) ─────────────────────────────────────────────
class _DocCard extends StatelessWidget {
  final _DocDef   doc;
  final File?     file;
  final String?   url;
  final bool      uploading;
  final bool      compact;
  final Map<String, dynamic>? rejection;
  final VoidCallback onTap;

  const _DocCard({
    required this.doc, required this.file, required this.url,
    required this.uploading, required this.onTap, this.compact = false,
    this.rejection,
  });

  bool get _isRejected => rejection != null;
  bool get _isDone => url != null && !_isRejected;

  @override
  Widget build(BuildContext context) {
    if (compact) return _buildCompact();
    return GestureDetector(
      onTap: uploading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _boxDecoration(),
        child: Row(children: [
          _preview(64),
          const SizedBox(width: 14),
          Expanded(child: _textCol(13)),
          _actionBtn(),
        ]),
      ),
    );
  }

  // Version compacte : empilée verticalement pour recto/verso côte à côte
  Widget _buildCompact() => GestureDetector(
    onTap: uploading ? null : onTap,
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: _boxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _preview(56),
          const SizedBox(height: 8),
          _textCol(11),
          const SizedBox(height: 6),
          _actionBtn(small: true),
        ],
      ),
    ),
  );

  BoxDecoration _boxDecoration() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(
      color: _isRejected
          ? AppColors.error
          : _isDone
              ? AppColors.successLight
              : AppColors.primary.withValues(alpha: 0.25),
      width: _isRejected || _isDone ? 1.5 : 1,
    ),
    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
  );

  Widget _preview(double size) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: SizedBox(
      width: size, height: size,
      child: uploading
          ? Container(
              color: AppColors.primary.withValues(alpha: 0.08),
              child: const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
            )
          : file != null
              ? Image.file(file!, fit: BoxFit.cover)
              : Container(
                  color: _isRejected
                      ? AppColors.error.withValues(alpha: 0.08)
                      : _isDone
                          ? AppColors.successLightBg
                          : AppColors.primary.withValues(alpha: 0.07),
                  child: Icon(
                    _isRejected
                        ? Icons.error_outline
                        : _isDone
                            ? Icons.check_circle_outline
                            : doc.icon,
                    color: _isRejected
                        ? AppColors.error
                        : _isDone
                            ? AppColors.successLight
                            : AppColors.primary,
                    size: size * 0.42,
                  ),
                ),
    ),
  );

  Widget _textCol(double fs) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(doc.label,
          style: TextStyle(fontSize: fs, fontWeight: FontWeight.w700,
              color: _isRejected
                  ? AppColors.error
                  : _isDone
                      ? const Color(0xFF1B5E20)
                      : AppColors.textDark)),
      const SizedBox(height: 2),
      Text(
        _isRejected
            ? 'Refusé : ${rejection!['reason']}'
            : _isDone
                ? 'Uploadé ✓'
                : doc.hint,
        maxLines: _isRejected ? 3 : 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: fs - 2,
            color: _isRejected
                ? AppColors.error
                : _isDone
                    ? AppColors.successLight
                    : AppColors.textMuted),
      ),
    ],
  );

  Widget _actionBtn({bool small = false}) => Container(
    padding: EdgeInsets.symmetric(horizontal: small ? 8 : 12, vertical: small ? 4 : 6),
    decoration: BoxDecoration(
      color: _isRejected
          ? AppColors.error.withValues(alpha: 0.10)
          : _isDone
              ? AppColors.successLightBg
              : AppColors.primary.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      _isRejected ? 'Corriger' : (_isDone ? 'Modifier' : 'Ajouter'),
      style: TextStyle(
        fontSize: small ? 10 : 11, fontWeight: FontWeight.w700,
        color: _isRejected
            ? AppColors.error
            : _isDone
                ? AppColors.successLight
                : AppColors.primary,
      ),
    ),
  );
}

class _SourceBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SourceBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 14),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 15)),
        ],
      ),
    ),
  );
}
