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

  /// Si une navbar suit juste en dessous (mode accueil), elle réserve déjà
  /// elle-même l'encoche bas de l'écran (voir _ClientNavBar) — inutile que
  /// la feuille l'ajoute une seconde fois, ça ne ferait qu'écarter les
  /// boutons de service de la navbar sans raison. À mettre à false dans ce
  /// cas ; laissé à true (par défaut) pour l'assistant, qui n'a pas de
  /// navbar sous lui et doit donc respecter l'encoche lui-même.
  final bool addBottomSafeArea;

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
    this.addBottomSafeArea = true,
  });

  @override
  Widget build(BuildContext context) {
    final maxOffset = panelHeight - minPanelContent;

    void toggleCollapse() {
      onDraggingChanged(false);
      onDragOffsetChanged(dragOffset == 0 ? max(0.0, maxOffset) : 0.0);
    }

    // Plus d'Align(bottomCenter) ici — inutile depuis que ce widget est posé
    // directement dans un Column (voir client_home_shell_screen.dart, même
    // schéma que home_driver_screen.dart : boutons flottants + feuille dans
    // UN SEUL Column empilé en bas, plutôt que des Positioned calculés à la
    // main). C'est ce Column, pas cet Align, qui ancre la feuille en bas.
    return AnimatedContainer(
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
          bottom: addBottomSafeArea,
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
              //
              // Cette hauteur est RE-mesurée à chaque frame pendant qu'une
              // étape/un mode change (voir _measureSheetHeightFrame côté
              // ClientHomeShellScreen) — donc sa cible bouge en continu
              // pendant ~200-300ms à chaque changement de contenu, PAS
              // seulement pendant un glissé. Avec une durée longue (280ms,
              // valeur d'origine) cet AnimatedContainer se relance sur
              // chaque frame avant d'avoir eu le temps de rattraper sa
              // cible précédente : la feuille "traîne" visiblement derrière
              // le contenu (déjà lissé, lui, par AnimatedSize) au lieu de
              // le suivre — lenteur perçue rapportée en test sur les 3
              // modes (accueil, Express/Simple, Groupée, qui partagent tous
              // ce socle). Une durée courte laisse cet habillage EXTÉRIEUR
              // suivre de près la vraie animation (celle d'AnimatedSize,
              // déjà la source du mouvement perçu comme fluide) au lieu de
              // lui imposer sa propre course en plus — tout en gardant un
              // vrai fondu pour l'ouverture/fermeture au glissé.
              AnimatedContainer(
                duration: isDragging
                    ? Duration.zero
                    : const Duration(milliseconds: 120),
                curve: Curves.easeOut,
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
                          // Glissé + fondu, comme le socle livreur — un
                          // léger déplacement vertical (pas un plein écran
                          // comme sur home_driver_screen.dart, ici le
                          // contenu change à chaque étape, pas à chaque
                          // changement de mode : une glisse discrète évite
                          // l'effet "saccadé" d'un simple fondu sec.
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (transitionChild, anim) =>
                                SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.05),
                                    end: Offset.zero,
                                  ).animate(anim),
                                  child: FadeTransition(
                                    opacity: anim,
                                    child: transitionChild,
                                  ),
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
    );
  }
}
