import 'package:flutter/material.dart';

/// Bouton d'appel circulaire vert — partagé entre les écrans de navigation
/// livreur (course simple, tournée batch) pour que l'action "appeler" ait
/// toujours la même apparence, au lieu d'un style différent par écran.
class CallButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;

  const CallButton({super.key, required this.onTap, this.size = 54});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFF00C853),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.phone, color: Colors.white, size: size * 0.44),
      ),
    );
  }
}
