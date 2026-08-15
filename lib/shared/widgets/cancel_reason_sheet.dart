import 'package:flutter/material.dart';

import '../../core/theme/client_text.dart';
import 'gradient_sheet.dart';

/// Motifs suggérés au client qui annule une commande — "Ignorer" est
/// toujours proposé en plus par [showCancelReasonSheet] elle-même.
const kClientCancelReasons = [
  'J\'ai changé d\'avis',
  'Erreur dans l\'adresse ou les infos',
  'Le livreur met trop de temps',
  'J\'ai trouvé une autre solution',
  'Autre',
];

/// Motifs suggérés au livreur qui annule une course déjà acceptée.
const kDriverCancelReasons = [
  'Problème avec mon véhicule',
  'Impossible de joindre le client',
  'Adresse introuvable',
  'Urgence personnelle',
  'Autre',
];

/// Feuille "Pourquoi annulez-vous ?" — proposée au client comme au livreur
/// avant de confirmer une annulation. Chaque motif choisi ferme directement
/// la feuille (pas de bouton "Valider" séparé — un tap suffit), et
/// "Ignorer" reste toujours disponible pour annuler sans se justifier.
///
/// Retourne le libellé du motif choisi, ou `null` si l'utilisateur a préféré
/// ignorer / a fermé la feuille sans choisir.
Future<String?> showCancelReasonSheet(
  BuildContext context, {
  required List<String> reasons,
  String title = 'Pourquoi annulez-vous ?',
}) {
  return showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => GradientSheet(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(sheetCtx).viewPadding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetDragHandle(),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: ClientText.title.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            'Facultatif — vous pouvez aussi ignorer',
            textAlign: TextAlign.center,
            style: ClientText.label.copyWith(
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 20),
          for (final reason in reasons) ...[
            _ReasonTile(
              label: reason,
              onTap: () => Navigator.of(sheetCtx).pop(reason),
            ),
            const SizedBox(height: 10),
          ],
          TextButton(
            onPressed: () => Navigator.of(sheetCtx).pop(null),
            child: Text(
              'Ignorer',
              style: ClientText.body.copyWith(
                color: Colors.white.withValues(alpha: 0.70),
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ReasonTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ReasonTile({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: ClientText.body.copyWith(color: Colors.white),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.5),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
