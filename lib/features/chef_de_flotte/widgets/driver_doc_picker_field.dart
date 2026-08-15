import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/pressable.dart';

/// Champ document pour un livreur existant — même look que
/// [DocPickerField] (feuille caméra/galerie, vignette) mais sans
/// upload immédiat : le fichier choisi reste local, remonté au parent
/// via [onChanged], pour permettre d'envoyer plusieurs documents en un
/// seul appel réseau (voir chef_de_flotte_driver_detail_screen.dart).
class DriverDocPickerField extends StatefulWidget {
  final String label;
  final String? existingUrl;
  final void Function(File? file) onChanged;

  const DriverDocPickerField({
    super.key,
    required this.label,
    required this.onChanged,
    this.existingUrl,
  });

  @override
  State<DriverDocPickerField> createState() => _DriverDocPickerFieldState();
}

class _DriverDocPickerFieldState extends State<DriverDocPickerField> {
  final _picker = ImagePicker();
  File? _localFile;

  Future<void> _pick(ImageSource source) async {
    Navigator.of(context).pop();
    final file = await _picker.pickImage(source: source, imageQuality: 85);
    if (file == null || !mounted) return;
    setState(() => _localFile = File(file.path));
    widget.onChanged(_localFile);
  }

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _PickOption(
                      icon: Icons.camera_alt_outlined,
                      label: 'Appareil photo',
                      color: AppColors.primary,
                      onTap: () => _pick(ImageSource.camera),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PickOption(
                      icon: Icons.photo_library_outlined,
                      label: 'Galerie',
                      color: AppColors.primaryMid,
                      onTap: () => _pick(ImageSource.gallery),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLocal = _localFile != null;
    final hasExisting = !hasLocal && widget.existingUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 6),
        Pressable(
          onTap: _showPicker,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (hasLocal || hasExisting)
                  ? (hasLocal ? Colors.orange.shade50 : Colors.green.shade50)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasLocal
                    ? Colors.orange.shade300
                    : hasExisting
                    ? Colors.green.shade300
                    : Colors.grey.shade200,
                width: (hasLocal || hasExisting) ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: hasLocal
                      ? Image.file(
                          _localFile!,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                        )
                      : hasExisting
                      ? Image.network(
                          widget.existingUrl!,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholderIcon(),
                        )
                      : Container(
                          width: 44,
                          height: 44,
                          color: Colors.grey.shade100,
                          child: const Icon(
                            Icons.upload_file_outlined,
                            color: Color(0xFF9CA3AF),
                            size: 20,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasLocal) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.upload_rounded,
                              color: Colors.orange.shade700,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Nouveau — à enregistrer',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ],
                        ),
                      ] else if (hasExisting) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.green.shade600,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Document ajouté',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.green.shade800,
                              ),
                            ),
                          ],
                        ),
                      ] else
                        const Text(
                          'Appuyer pour ajouter',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF374151),
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Colors.grey.shade400,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _placeholderIcon() => Container(
    width: 44,
    height: 44,
    color: AppColors.primary.withValues(alpha: 0.15),
    child: const Icon(
      Icons.description_outlined,
      color: AppColors.primary,
      size: 22,
    ),
  );
}

class _PickOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PickOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );
}
