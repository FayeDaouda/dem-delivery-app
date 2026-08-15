import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Socle de feuille partagé par les 3 modes de l'accueil client (Accueil,
/// Express/Simple, Groupée) — extrait de l'ancien order_create_screen.dart
/// (le plus complet des 2 mécanismes d'origine : c'est le seul des deux à
/// avoir le tiroir rétractable au glissé). Un seul exemplaire de ce
/// mécanisme, plutôt qu'une copie par écran — il a déjà causé plusieurs bugs
/// de débordement cette session, même isolé dans un seul écran à la fois.
///
/// Le fond dégradé reste ancré au bas de l'écran en toutes circonstances
/// (jamais décalé par un margin lié au clavier) — seul le CONTENU (Column)
/// reçoit un padding animé, ce qui fait aussi grandir le panneau vers le
/// haut quand le clavier s'ouvre.
class HomeClientSheetScaffold extends StatelessWidget {
  /// Clé posée sur le nœud mesuré (voir ClientHomeShellScreen._measureSheetHeight).
  final GlobalKey sheetKey;

  /// Hauteur "pleine" actuelle du panneau — mesurée (ou estimation de
  /// repli avant la première mesure), PAS réduite par [dragOffset].
  final double panelHeight;

  /// Décalage courant du tiroir rétractable au glissé (0 = totalement ouvert).
  final double dragOffset;
  final bool isDragging;
  final double keyboardHeight;
  final double minPanelContent;

  final ValueChanged<bool> onDraggingChanged;
  final ValueChanged<double> onDragOffsetChanged;

  /// Contenu du mode/étape courante — l'appelant doit l'envelopper dans une
  /// KeyedSubtree avec une Key distincte par mode/étape : c'est cette Key
  /// qui déclenche la transition d'AnimatedSwitcher ci-dessous.
  final Widget child;

  /// Appelé quand l'utilisateur tape dans une zone vide du panneau — les
  /// écrans avec clavier (Express/Simple/Groupée) l'utilisent pour le
  /// refermer ; l'accueil (pas de champ texte) peut passer un no-op.
  final VoidCallback onTapDismissKeyboard;

  const HomeClientSheetScaffold({
    super.key,
    required this.sheetKey,
    required this.panelHeight,
    required this.dragOffset,
    required this.isDragging,
    required this.keyboardHeight,
    required this.onDraggingChanged,
    required this.onDragOffsetChanged,
    required this.child,
    required this.onTapDismissKeyboard,
    this.minPanelContent = 66.0,
  });

  @override
  Widget build(BuildContext context) {
    final maxOffset = panelHeight - minPanelContent;

    void toggleCollapse() {
      onDraggingChanged(false);
      onDragOffsetChanged(dragOffset == 0 ? max(0.0, maxOffset) : 0.0);
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: AppColors.gradientSplash,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOut,
          padding: EdgeInsets.only(bottom: keyboardHeight),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragStart: (_) => onDraggingChanged(true),
                  onVerticalDragUpdate: (d) {
                    onDragOffsetChanged(
                      (dragOffset + d.delta.dy).clamp(0.0, max(0.0, maxOffset)),
                    );
                  },
                  onVerticalDragEnd: (d) {
                    final v = d.primaryVelocity ?? 0;
                    onDraggingChanged(false);
                    onDragOffsetChanged(
                      (v > 200 || dragOffset > maxOffset / 2)
                          ? max(0.0, maxOffset)
                          : 0.0,
                    );
                  },
                  onTap: toggleCollapse,
                  child: SizedBox(
                    width: double.infinity,
                    height: 22,
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 3,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),

                // Contenu via AnimatedSize + AnimatedSwitcher — épouse la
                // vraie hauteur du contenu affiché (voir _sheetKey/mesure
                // côté ClientHomeShellScreen), avec le tiroir rétractable
                // au glissé posé par-dessus (AnimatedContainer + OverflowBox).
                AnimatedContainer(
                  duration: isDragging
                      ? Duration.zero
                      : const Duration(milliseconds: 280),
                  curve: Curves.easeInOut,
                  height: max(minPanelContent, panelHeight - dragOffset),
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.bottomCenter,
                      minHeight: 0,
                      // Plafond de sécurité générique — jamais `panelHeight`
                      // elle-même, sinon la mesure ne pourrait jamais
                      // détecter qu'un mode a besoin de PLUS de place que le
                      // dernier mesuré (circularité).
                      maxHeight: MediaQuery.of(context).size.height * 0.62,
                      // Un tap dans une zone vide referme le clavier.
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onTapDismissKeyboard,
                        child: Container(
                          key: sheetKey,
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            // bottomCenter — doit matcher l'alignment de
                            // l'OverflowBox ci-dessus (tiroir à glisser).
                            // Avec des alignments opposés, le contenu du
                            // haut de la feuille apparaît tronqué/fantôme
                            // pendant la transition (bug déjà rencontré et
                            // corrigé sur order_create_screen.dart).
                            alignment: Alignment.bottomCenter,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              transitionBuilder: (transitionChild, anim) =>
                                  FadeTransition(
                                    opacity: anim,
                                    child: transitionChild,
                                  ),
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
