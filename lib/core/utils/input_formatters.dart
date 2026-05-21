import 'package:flutter/services.dart';

/// Autorise uniquement les lettres Unicode (Latin, accents, wolof, arabe…),
/// espaces, tirets et apostrophes. Bloque emojis et caractères spéciaux.
class NameInputFormatter extends TextInputFormatter {
  static final _blocked = RegExp(r'[^\p{L}\p{M} \-\x27]', unicode: true);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue nv) {
    final cleaned = nv.text.replaceAll(_blocked, '');
    if (cleaned == nv.text) return nv;
    return nv.copyWith(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
    );
  }
}

/// Autorise uniquement les chiffres (pour les champs téléphone sans préfixe).
class DigitsOnlyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue nv) {
    final cleaned = nv.text.replaceAll(RegExp(r'\D'), '');
    if (cleaned == nv.text) return nv;
    return nv.copyWith(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
    );
  }
}
