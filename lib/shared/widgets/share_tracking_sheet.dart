import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class ShareTrackingSheet {
  static void show(BuildContext context, {required String orderId}) {
    final url = 'https://api.dem.sn/track/$orderId';
    final msg = 'Suivez ma livraison DEM en temps réel : $url';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _Sheet(msg: msg),
    );
  }
}

class _Sheet extends StatelessWidget {
  final String msg;
  const _Sheet({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0CB8DE), Color(0xFF0671BA)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Partager le suivi',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Permettez au destinataire de suivre le livreur en temps réel.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // WhatsApp
            _ShareTile(
              icon: SvgPicture.asset('assets/icons/whatsapp.svg', width: 24, height: 24,
                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
              iconBg: const Color(0xFF25D366),
              label: 'WhatsApp',
              subtitle: 'Envoyer directement via WhatsApp',
              onTap: () {
                Navigator.pop(context);
                launchUrl(
                  Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}'),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
            const SizedBox(height: 12),

            // Autres options
            _ShareTile(
              icon: const Icon(Icons.share_outlined, color: Colors.white, size: 22),
              iconBg: Colors.white.withValues(alpha: 0.2),
              label: 'Autres options',
              subtitle: 'SMS, Email, Copier le lien...',
              onTap: () {
                Navigator.pop(context);
                SharePlus.instance.share(ShareParams(text: msg));
              },
            ),
          ]),
        ),
      ),
    );
  }
}

class _ShareTile extends StatelessWidget {
  final Widget icon;
  final Color iconBg;
  final String label, subtitle;
  final VoidCallback onTap;
  const _ShareTile({
    required this.icon, required this.iconBg,
    required this.label, required this.subtitle, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(child: icon),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
        ])),
        Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.5), size: 22),
      ]),
    ),
  );
}
