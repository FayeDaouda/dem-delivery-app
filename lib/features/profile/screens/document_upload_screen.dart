import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/api/api_client.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_theme.dart';

class DocumentUploadScreen extends StatefulWidget {
  const DocumentUploadScreen({super.key});

  @override
  State<DocumentUploadScreen> createState() => _DocumentUploadScreenState();
}

class _DocumentUploadScreenState extends State<DocumentUploadScreen> {
  // Chemins locaux sélectionnés
  final Map<String, File?> _files = {
    'idCardFront':  null,
    'idCardBack':   null,
    'licenseFront': null,
    'licenseBack':  null,
  };

  // URLs après upload réussi
  final Map<String, String?> _urls = {
    'idCardFront':  null,
    'idCardBack':   null,
    'licenseFront': null,
    'licenseBack':  null,
  };

  final Map<String, bool> _uploading = {
    'idCardFront':  false,
    'idCardBack':   false,
    'licenseFront': false,
    'licenseBack':  false,
  };

  final _picker = ImagePicker();

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
      final res = await ApiClient.dio.post('/users/driver/documents', data: form);
      final user = res.data['user'] as Map<String, dynamic>?;
      if (user != null && mounted) {
        setState(() => _urls[field] = user[field] as String?);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.current.uploadSuccess),
            backgroundColor: const Color(0xFF22C55E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading[field] = false);
    }
  }

  void _showSourcePicker(String field) {
    final s = AppStrings.current;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0CB8DE), Color(0xFF0671BA), Color(0xFF04317C)],
          ),
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
              label: s.takePhoto,
              onTap: () { Navigator.pop(context); _pick(field, ImageSource.camera); },
            ),
            const SizedBox(height: 10),
            _SourceBtn(
              icon: Icons.photo_library_outlined,
              label: s.fromGallery,
              onTap: () { Navigator.pop(context); _pick(field, ImageSource.gallery); },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.current;
    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            decoration: const BoxDecoration(gradient: AppColors.gradientSplash),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                    ),
                    const Spacer(),
                    Text(s.documents,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
          ),

          // Corps
          Expanded(
            child: Container(
              color: AppColors.surface,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Info banner
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Photos lisibles, bien éclairées. JPG/PNG, max 5 Mo.',
                            style: TextStyle(color: AppColors.primary.withValues(alpha: 0.9), fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Carte d'identité ──
                  _SectionTitle(label: s.idCard, icon: Icons.badge_outlined),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _DocSlot(
                        label: s.idCardFrontLabel,
                        field: 'idCardFront',
                        file: _files['idCardFront'],
                        uploading: _uploading['idCardFront']!,
                        uploaded: _urls['idCardFront'] != null,
                        onTap: () => _showSourcePicker('idCardFront'),
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: _DocSlot(
                        label: s.idCardBackLabel,
                        field: 'idCardBack',
                        file: _files['idCardBack'],
                        uploading: _uploading['idCardBack']!,
                        uploaded: _urls['idCardBack'] != null,
                        onTap: () => _showSourcePicker('idCardBack'),
                      )),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Permis ──
                  _SectionTitle(label: s.license, icon: Icons.credit_card_outlined),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _DocSlot(
                        label: s.licenseFrontLabel,
                        field: 'licenseFront',
                        file: _files['licenseFront'],
                        uploading: _uploading['licenseFront']!,
                        uploaded: _urls['licenseFront'] != null,
                        onTap: () => _showSourcePicker('licenseFront'),
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: _DocSlot(
                        label: s.licenseBackLabel,
                        field: 'licenseBack',
                        file: _files['licenseBack'],
                        uploading: _uploading['licenseBack']!,
                        uploaded: _urls['licenseBack'] != null,
                        onTap: () => _showSourcePicker('licenseBack'),
                      )),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Slot document (photo recto/verso) ─────────────────────────────────────────
class _DocSlot extends StatelessWidget {
  final String label;
  final String field;
  final File? file;
  final bool uploading;
  final bool uploaded;
  final VoidCallback onTap;

  const _DocSlot({
    required this.label,
    required this.field,
    required this.file,
    required this.uploading,
    required this.uploaded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: uploading ? null : onTap,
      child: AspectRatio(
        aspectRatio: 3 / 2,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: uploaded
                  ? const Color(0xFF22C55E)
                  : AppColors.primary.withValues(alpha: 0.30),
              width: uploaded ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: uploading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
                : file != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(file!, fit: BoxFit.cover),
                          if (uploaded)
                            Positioned(
                              top: 6, right: 6,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF22C55E), shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.check, color: Colors.white, size: 12),
                              ),
                            ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              color: AppColors.primary.withValues(alpha: 0.7), size: 28),
                          const SizedBox(height: 6),
                          Text(
                            label,
                            style: TextStyle(
                              color: AppColors.textSecondary.withValues(alpha: 0.8),
                              fontSize: 10,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionTitle({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700,
            )),
      ],
    );
  }
}

class _SourceBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SourceBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
}
