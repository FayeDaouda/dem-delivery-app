import 'package:flutter/material.dart';

import '../../core/services/places_autocomplete_service.dart';

/// Palette utilisée par [PlaceSuggestionsList] — un jeu de couleurs par écran
/// (chaque écran a son propre thème : DEM Pro sombre, client sombre bleu,
/// favoris clair) plutôt qu'un widget qui impose sa propre palette.
class PlaceSuggestionsColors {
  final Color background;
  final Color border;
  final Color divider;
  final Color iconBg;
  final Color icon;
  final Color mainText;
  final Color secondaryText;
  final Color accent;
  final Color shadow;
  const PlaceSuggestionsColors({
    required this.background,
    required this.border,
    required this.divider,
    required this.iconBg,
    required this.icon,
    required this.mainText,
    required this.secondaryText,
    required this.accent,
    this.shadow = const Color(0x59000000),
  });
}

/// Liste de suggestions d'adresses Google Places — icône selon le type de
/// lieu, portion recherchée en gras, état de chargement/erreur avec retry,
/// et attribution "Powered by Google" (requise par les CGU Google Places).
class PlaceSuggestionsList extends StatelessWidget {
  final List<Map<String, dynamic>> suggestions;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final PlaceSuggestionsColors colors;
  final double maxHeight;
  final double borderRadius;

  const PlaceSuggestionsList({
    super.key,
    required this.suggestions,
    required this.onSelect,
    required this.colors,
    this.loading = false,
    this.error,
    this.onRetry,
    this.maxHeight = 260,
    this.borderRadius = 14,
  });

  @override
  Widget build(BuildContext context) {
    if (!loading && error == null && suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: colors.border),
        boxShadow: [BoxShadow(color: colors.shadow, blurRadius: 16)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: loading
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(color: colors.accent, strokeWidth: 2),
                  ),
                ),
              )
            : error != null
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(children: [
                      Icon(Icons.error_outline, color: colors.secondaryText, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(error!, style: TextStyle(color: colors.secondaryText, fontSize: 12))),
                      if (onRetry != null)
                        GestureDetector(
                          onTap: onRetry,
                          child: Text('Réessayer', style: TextStyle(color: colors.accent, fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                    ]),
                  )
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: suggestions.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: colors.divider),
                        itemBuilder: (_, i) => _SuggestionTile(
                          place: suggestions[i],
                          colors: colors,
                          onTap: () => onSelect(suggestions[i]),
                        ),
                      ),
                    ),
                    _PoweredByGoogle(colors: colors),
                  ]),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final Map<String, dynamic> place;
  final PlaceSuggestionsColors colors;
  final VoidCallback onTap;
  const _SuggestionTile({required this.place, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fmt = place['structured_formatting'] as Map<String, dynamic>?;
    final main = fmt?['main_text'] as String? ?? place['description'] as String? ?? '';
    final secondary = fmt?['secondary_text'] as String? ?? '';
    final types = place['types'] as List<dynamic>?;
    final icon = PlacesAutocompleteService.iconForTypes(types);

    final matches = (fmt?['main_text_matched_substrings'] as List?)?.cast<Map<String, dynamic>>();
    final match = matches != null && matches.isNotEmpty ? matches.first : null;
    final offset = (match?['offset'] as num?)?.toInt() ?? 0;
    final length = (match?['length'] as num?)?.toInt() ?? 0;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: colors.iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: colors.icon, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _highlighted(main, offset, length, colors.mainText),
                if (secondary.isNotEmpty)
                  Text(secondary,
                      style: TextStyle(color: colors.secondaryText, fontSize: 11.5),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _highlighted(String text, int offset, int length, Color color) {
    if (length <= 0 || offset < 0 || offset + length > text.length) {
      return Text(text,
          style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
          maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    final before = text.substring(0, offset);
    final matched = text.substring(offset, offset + length);
    final after = text.substring(offset + length);
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500),
        children: [
          TextSpan(text: before),
          TextSpan(text: matched, style: const TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: after),
        ],
      ),
    );
  }
}

class _PoweredByGoogle extends StatelessWidget {
  final PlaceSuggestionsColors colors;
  const _PoweredByGoogle({required this.colors});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
    child: Align(
      alignment: Alignment.centerRight,
      child: Text(
        'Résultats — Powered by Google',
        style: TextStyle(color: colors.secondaryText.withValues(alpha: 0.7), fontSize: 9.5),
      ),
    ),
  );
}
