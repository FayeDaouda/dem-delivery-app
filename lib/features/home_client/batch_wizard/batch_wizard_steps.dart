import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';
import '../../../core/utils/price_format.dart';
import '../../../shared/widgets/colored_address_field.dart';
import '../../../shared/widgets/contact_mini_field.dart';
import '../../../shared/widgets/contact_picker.dart';
import '../../../shared/widgets/favorite_address_chips.dart';
import '../../../shared/widgets/place_suggestions_list.dart';
import '../../../shared/widgets/pressable.dart';
import '../../../shared/widgets/primary_button.dart';
import 'batch_wizard_controller.dart';

/// Widgets de présentation du parcours Groupée — transplantés quasi tels
/// quels depuis l'ancien batch_create_screen.dart (voir _TrajetStep..
/// _ResumeStep), sur le même modèle que order_wizard_steps.dart : purs,
/// pilotés uniquement par des callbacks/paramètres fournis par
/// BatchWizardController.
///
/// Accent visuel harmonisé sur AppColors.accentIndigo — la même couleur que
/// la tuile "Groupée" de l'accueil (voir client_home_shell_screen.dart),
/// remplace l'ancien vert `_kBatchAccent` isolé de batch_create_screen.dart,
/// pour que l'identité visuelle du mode reste cohérente entre la tuile et
/// tout son parcours.
const _batchAccent = AppColors.accentIndigo;
const _batchPlaceSuggestionsColors = PlaceSuggestionsColors(
  background: AppColors.card,
  border: Colors.white24,
  divider: _batchAccent,
  iconBg: _batchAccent,
  icon: Colors.white,
  mainText: Colors.white,
  secondaryText: _batchAccent,
  accent: _batchAccent,
);

// ── Étape 0 — Trajet ─────────────────────────────────────────────────────────
class BatchStep0Panel extends StatelessWidget {
  final TextEditingController pickupCtrl;
  final FocusNode pickupFocus;
  final bool pickupConfirmed;
  final bool pickupManualEntry;
  final List<BatchStopEntry> stops;
  final Object? activeField;
  final List<Map<String, dynamic>> suggestions;
  final bool searching;
  final String? searchError;
  final List<Map<String, dynamic>> favorites;
  final ValueChanged<Map<String, dynamic>> onSelectFavorite;
  final VoidCallback onPickupTap;
  final ValueChanged<int> onStopTap;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Map<String, dynamic>> onSelectSuggestion;
  final VoidCallback onRetryAddressSearch;
  final VoidCallback onPickupClear;
  final VoidCallback onAddStop;
  final ValueChanged<int> onRemoveStop;
  final ValueChanged<int> onClearStop;
  final VoidCallback onNext;
  final bool canNext;

  const BatchStep0Panel({
    super.key,
    required this.pickupCtrl,
    required this.pickupFocus,
    required this.pickupConfirmed,
    required this.pickupManualEntry,
    required this.stops,
    required this.activeField,
    required this.suggestions,
    required this.searching,
    required this.searchError,
    required this.favorites,
    required this.onSelectFavorite,
    required this.onPickupTap,
    required this.onStopTap,
    required this.onQueryChanged,
    required this.onSelectSuggestion,
    required this.onRetryAddressSearch,
    required this.onPickupClear,
    required this.onAddStop,
    required this.onRemoveStop,
    required this.onClearStop,
    required this.onNext,
    required this.canNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        // min : voir order_wizard_steps.dart — sans ça, ce Column remplit
        // systématiquement toute la hauteur allouée par AnimatedSize au lieu
        // de sa hauteur réelle, empêchant le panneau de s'adapter au contenu.
        mainAxisSize: MainAxisSize.min,
        children: [
          // SingleChildScrollView simple, sans Flexible — un Flexible ici
          // empêcherait AnimatedSize de détecter la vraie hauteur du contenu
          // (même piège déjà rencontré et corrigé sur order_create_screen.dart
          // et l'ancien batch_create_screen.dart).
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1 collecte, jusqu\'à $kBatchMaxStops destinations — -20% sur le total.',
                  style: ClientText.body.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                AddressField(
                  controller: pickupCtrl,
                  focusNode: pickupFocus,
                  hint: 'Adresse de collecte',
                  dotColor: AppColors.success,
                  active: activeField == 'pickup',
                  confirmed: pickupConfirmed,
                  readOnly: !pickupManualEntry,
                  onTap: onPickupTap,
                  onChanged: onQueryChanged,
                  onClear: onPickupClear,
                ),
                if (activeField == 'pickup' &&
                    (suggestions.isNotEmpty ||
                        searching ||
                        searchError != null))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: PlaceSuggestionsList(
                      suggestions: suggestions,
                      loading: searching,
                      error: searchError,
                      onRetry: onRetryAddressSearch,
                      colors: _batchPlaceSuggestionsColors,
                      onSelect: onSelectSuggestion,
                    ),
                  ),
                if (activeField == 'pickup' && favorites.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: FavoriteAddressChips(
                      favorites: favorites,
                      onSelect: onSelectFavorite,
                    ),
                  ),
                const SizedBox(height: 14),
                Text(
                  'Destinations (${stops.length}/$kBatchMaxStops)',
                  style: ClientText.bodyStrong.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < stops.length; i++) ...[
                  _StopCard(
                    index: i,
                    entry: stops[i],
                    canRemove: stops.length > kBatchMinStops,
                    onRemove: () => onRemoveStop(i),
                    onQueryChanged: onQueryChanged,
                    onTap: () => onStopTap(i),
                    onClear: () => onClearStop(i),
                    active: activeField == i,
                  ),
                  if (activeField == i &&
                      (suggestions.isNotEmpty ||
                          searching ||
                          searchError != null))
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 6),
                      child: PlaceSuggestionsList(
                        suggestions: suggestions,
                        loading: searching,
                        error: searchError,
                        onRetry: onRetryAddressSearch,
                        colors: _batchPlaceSuggestionsColors,
                        onSelect: onSelectSuggestion,
                      ),
                    ),
                  if (activeField == i && favorites.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: FavoriteAddressChips(
                        favorites: favorites,
                        onSelect: onSelectFavorite,
                      ),
                    ),
                  const SizedBox(height: 10),
                ],
                if (stops.length < kBatchMaxStops)
                  Pressable(
                    onTap: onAddStop,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add, color: Colors.white, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            'Ajouter un arrêt',
                            style: ClientText.body.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            label: 'Suivant — Expéditeur',
            trailingIcon: Icons.arrow_forward,
            onTap: canNext ? onNext : null,
          ),
        ],
      ),
    );
  }
}

class _StopCard extends StatelessWidget {
  final int index;
  final BatchStopEntry entry;
  final bool canRemove;
  final bool active;
  final VoidCallback onRemove;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onTap;
  final VoidCallback onClear;
  const _StopCard({
    required this.index,
    required this.entry,
    required this.canRemove,
    required this.active,
    required this.onRemove,
    required this.onQueryChanged,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Arrêt ${index + 1}',
                style: ClientText.body.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              if (canRemove)
                GestureDetector(
                  onTap: onRemove,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: AppColors.error,
                      size: 15,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          AddressField(
            controller: entry.addressCtrl,
            focusNode: entry.focusNode,
            hint: 'Adresse de destination',
            dotColor: AppColors.error,
            active: active,
            confirmed: entry.lat != null,
            readOnly: !entry.manualEntry,
            onTap: onTap,
            onChanged: onQueryChanged,
            onClear: onClear,
          ),
        ],
      ),
    );
  }
}

// ── Étape 1 — Expéditeur ─────────────────────────────────────────────────────
class BatchStep1Panel extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final VoidCallback onPickContact;
  final VoidCallback onPickMe;
  final VoidCallback onNext;

  const BatchStep1Panel({
    super.key,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.onPickContact,
    required this.onPickMe,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Veuillez renseigner les informations de l\'expéditeur',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Astuce : ',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Icon(
                  Icons.person_outline_rounded,
                  color: Colors.white.withValues(alpha: 0.70),
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  'sélectionnez un contact pour gagner du temps',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Pas d'Expanded ici — une seule carte, taille fixe (voir
          // commentaire équivalent dans l'ancien batch_create_screen.dart).
          SingleChildScrollView(
            child: ContactMiniField(
              label: 'Expéditeur',
              dotColor: AppColors.success,
              nameCtrl: nameCtrl,
              phoneCtrl: phoneCtrl,
              onPick: onPickContact,
              onPickMe: onPickMe,
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Suivant — Destinataire',
            trailingIcon: Icons.arrow_forward,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

// ── Étape 2 — Destinataire(s) ────────────────────────────────────────────────
class BatchStep2Panel extends StatelessWidget {
  final List<BatchStopEntry> stops;
  final VoidCallback onNext;
  const BatchStep2Panel({super.key, required this.stops, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Veuillez renseigner les informations des destinataires',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Astuce : ',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Icon(
                  Icons.person_outline_rounded,
                  color: Colors.white.withValues(alpha: 0.70),
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  'sélectionnez un contact pour gagner du temps',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            child: Column(
              children: [
                for (var i = 0; i < stops.length; i++) ...[
                  ContactMiniField(
                    label: 'Destinataire — Arrêt ${i + 1}',
                    dotColor: AppColors.error,
                    nameCtrl: stops[i].receiverNameCtrl,
                    phoneCtrl: stops[i].receiverPhoneCtrl,
                    onPick: () => pickContact(
                      context,
                      nameCtrl: stops[i].receiverNameCtrl,
                      phoneCtrl: stops[i].receiverPhoneCtrl,
                    ),
                  ),
                  if (i < stops.length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: 'Suivant — Résumé',
            trailingIcon: Icons.arrow_forward,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

// ── Étape 3 — Résumé ─────────────────────────────────────────────────────────
class BatchStep3Panel extends StatelessWidget {
  final String pickupLabel;
  final List<BatchStopEntry> stops;
  final Map<String, dynamic>? estimate;
  final bool estimating;
  final String? error;
  final bool ready;
  final bool submitting;
  final VoidCallback onEditTrajet;
  final VoidCallback onSubmit;

  const BatchStep3Panel({
    super.key,
    required this.pickupLabel,
    required this.stops,
    required this.estimate,
    required this.estimating,
    required this.error,
    required this.ready,
    required this.submitting,
    required this.onEditTrajet,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                GestureDetector(
                  onTap: onEditTrajet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.circle,
                              color: AppColors.success,
                              size: 12,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                pickupLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(
                              Icons.edit_outlined,
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.5,
                              ),
                              size: 14,
                            ),
                          ],
                        ),
                        for (final s in stops) ...[
                          Padding(
                            padding: const EdgeInsets.only(left: 5),
                            child: Container(
                              width: 2,
                              height: 12,
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: AppColors.error,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  s.addressCtrl.text,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _PriceSummary(
                  estimate: estimate,
                  estimating: estimating,
                  error: error,
                  ready: ready,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.payments_outlined,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.60),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Paiement en espèces à la livraison par défaut — le paiement en ligne sera aussi proposé une fois un livreur trouvé.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.60),
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: estimate != null
                ? 'Confirmer — ${formatFcfa((estimate!['total'] as num).toInt())}'
                : 'Confirmer la tournée',
            onTap: (estimate != null && !submitting) ? onSubmit : null,
            loading: submitting,
          ),
        ],
      ),
    );
  }
}

class _PriceSummary extends StatelessWidget {
  final Map<String, dynamic>? estimate;
  final bool estimating;
  final String? error;
  final bool ready;
  const _PriceSummary({
    required this.estimate,
    required this.estimating,
    required this.error,
    required this.ready,
  });

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white38, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Renseignez la collecte et au moins $kBatchMinStops destinations pour voir le prix.',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }
    if (estimating) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: CircularProgressIndicator(color: _batchAccent, strokeWidth: 2),
        ),
      );
    }
    if (error != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          error!,
          style: const TextStyle(color: AppColors.error, fontSize: 12),
        ),
      );
    }
    if (estimate == null) return const SizedBox.shrink();

    final rawTotal = (estimate!['rawTotal'] as num).toInt();
    final discount = (estimate!['discountAmount'] as num).toInt();
    final total = (estimate!['total'] as num).toInt();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Total tournée',
                style: ClientText.body.copyWith(color: Colors.white70),
              ),
              const Spacer(),
              if (discount > 0)
                Text(
                  formatFcfa(rawTotal),
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 13,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              const SizedBox(width: 8),
              Text(
                formatFcfa(total),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (discount > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.successBright,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Vous économisez ${formatFcfa(discount)} en groupant vos livraisons',
                    style: const TextStyle(
                      color: AppColors.successBright,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
