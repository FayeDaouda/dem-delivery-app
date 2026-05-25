import 'package:flutter/material.dart';

void showDemToast(BuildContext context, String message, {bool isError = false}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _DemToastBanner(
      message: message,
      isError: isError,
      onDismiss: () { if (entry.mounted) entry.remove(); },
    ),
  );
  overlay.insert(entry);
  Future.delayed(const Duration(seconds: 4), () {
    if (entry.mounted) entry.remove();
  });
}

class _DemToastBanner extends StatefulWidget {
  final String message;
  final bool isError;
  final VoidCallback onDismiss;
  const _DemToastBanner({required this.message, required this.isError, required this.onDismiss});

  @override
  State<_DemToastBanner> createState() => _DemToastBannerState();
}

class _DemToastBannerState extends State<_DemToastBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 340));
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).viewPadding.top + 12;
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: widget.onDismiss,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: widget.isError
                    ? const LinearGradient(colors: [Color(0xFFFF5252), Color(0xFFB71C1C)])
                    : const LinearGradient(
                        colors: [Color(0xFF00D4FF), Color(0xFF0077B6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: (widget.isError ? const Color(0xFFFF5252) : const Color(0xFF00D4FF))
                        .withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    widget.isError ? Icons.error_outline : Icons.check_circle_outline,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
