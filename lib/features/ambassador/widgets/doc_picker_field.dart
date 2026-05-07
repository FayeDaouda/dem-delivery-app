import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';

class DocPickerField extends StatefulWidget {
  final String  label;
  final bool    isRequired;
  final String  fieldKey;
  final String? initialUrl;
  final void Function(String? url) onChanged;

  const DocPickerField({
    super.key,
    required this.label,
    required this.fieldKey,
    required this.onChanged,
    this.isRequired = false,
    this.initialUrl,
  });

  @override
  State<DocPickerField> createState() => _DocPickerFieldState();
}

class _DocPickerFieldState extends State<DocPickerField> {
  final _picker = ImagePicker();
  String? _url;
  bool    _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _url = widget.initialUrl;
  }

  Future<void> _pick(ImageSource source) async {
    Navigator.of(context).pop();
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 85);
      if (file == null) return;

      setState(() { _uploading = true; _error = null; });

      final formData = FormData.fromMap({
        'file':  await MultipartFile.fromFile(file.path, filename: file.name),
        'field': widget.fieldKey,
      });

      final res = await ApiClient.dio.post('/users/driver/documents', data: formData);
      final url = res.data['user']?[widget.fieldKey] as String?;

      if (url != null) {
        setState(() => _url = url);
        widget.onChanged(url);
      }
    } on DioException catch (e) {
      setState(() => _error = e.response?.data?['message'] ?? 'Erreur lors de l\'envoi.');
    } catch (_) {
      setState(() => _error = 'Erreur lors de l\'envoi.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1F2937))),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _PickOption(
                icon: Icons.camera_alt_outlined,
                label: 'Appareil photo',
                color: AppColors.primary,
                onTap: () => _pick(ImageSource.camera),
              )),
              const SizedBox(width: 12),
              Expanded(child: _PickOption(
                icon: Icons.photo_library_outlined,
                label: 'Galerie',
                color: AppColors.primaryMid,
                onTap: () => _pick(ImageSource.gallery),
              )),
            ]),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        RichText(
          text: TextSpan(
            text: widget.label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
            children: [
              if (widget.isRequired)
                const TextSpan(text: ' *', style: TextStyle(color: AppColors.primary)),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // Container principal
        GestureDetector(
          onTap: _uploading ? null : _showPicker,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _url != null
                  ? Colors.green.shade50
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _error != null
                    ? Colors.red.shade300
                    : _url != null
                        ? Colors.green.shade300
                        : Colors.grey.shade200,
                width: _url != null ? 1.5 : 1,
              ),
            ),
            child: _uploading
                ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                    SizedBox(width: 10),
                    Text('Envoi en cours…', style: TextStyle(color: AppColors.primaryMid, fontSize: 13)),
                  ])
                : _url != null
                    ? _DoneState(url: _url!, onEdit: _showPicker)
                    : _EmptyState(label: widget.label),
          ),
        ),

        // Erreur
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_error!, style: TextStyle(color: Colors.red.shade600, fontSize: 11)),
          ),
      ],
    );
  }
}

// ── État vide ─────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final String label;
  const _EmptyState({required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 40, height: 40,
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
      child: const Icon(Icons.upload_file_outlined, color: Color(0xFF9CA3AF), size: 20),
    ),
    const SizedBox(width: 12),
    const Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Appuyer pour ajouter', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
        SizedBox(height: 2),
        Text('Photo ou galerie', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
      ]),
    ),
    Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 18),
  ]);
}

// ── État rempli ───────────────────────────────────────────────────────────────
class _DoneState extends StatelessWidget {
  final String url;
  final VoidCallback onEdit;
  const _DoneState({required this.url, required this.onEdit});
  @override
  Widget build(BuildContext context) => Row(children: [
    ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 44, height: 44,
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, stack) => Container(
          width: 44, height: 44,
          color: AppColors.primary.withValues(alpha: 0.15),
          child: const Icon(Icons.description_outlined, color: AppColors.primary, size: 22),
        ),
      ),
    ),
    const SizedBox(width: 12),
    Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.check_circle, color: Colors.green.shade600, size: 14),
          const SizedBox(width: 4),
          Text('Document ajouté', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.green.shade800)),
        ]),
        const SizedBox(height: 2),
        Text(
          url.length > 32 ? '…${url.substring(url.length - 30)}' : url,
          style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
          overflow: TextOverflow.ellipsis,
        ),
      ]),
    ),
    TextButton(
      onPressed: onEdit,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primaryMid,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text('Modifier', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
  ]);
}

// ── Option dans la bottom sheet ───────────────────────────────────────────────
class _PickOption extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  final VoidCallback onTap;
  const _PickOption({required this.icon, required this.label, required this.color, required this.onTap});
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
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ]),
    ),
  );
}
