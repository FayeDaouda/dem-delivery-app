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

/// Formate une plaque d'immatriculation sénégalaise au fil de la saisie
/// (ex: "DK 1234 AB") — partagé entre l'inscription et l'édition du profil
/// pour que la même règle de saisie/normalisation s'applique partout.
class PlateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // On garde uniquement lettres et chiffres, en majuscules
    final raw = newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (raw.isEmpty) return newValue.copyWith(text: '');

    final buf = StringBuffer();
    int i = 0;

    // 1-2 lettres préfixe (ex: "DK")
    while (i < raw.length && i < 2 && RegExp(r'[A-Z]').hasMatch(raw[i])) {
      buf.write(raw[i++]);
    }
    // chiffres (max 4)
    if (i < raw.length) {
      final digits = StringBuffer();
      while (i < raw.length && digits.length < 4 && RegExp(r'\d').hasMatch(raw[i])) {
        digits.write(raw[i++]);
      }
      if (digits.isNotEmpty) { buf.write(' '); buf.write(digits); }
    }
    // lettres suffixe (max 2)
    if (i < raw.length) {
      final suffix = StringBuffer();
      while (i < raw.length && suffix.length < 2 && RegExp(r'[A-Z]').hasMatch(raw[i])) {
        suffix.write(raw[i++]);
      }
      if (suffix.isNotEmpty) { buf.write(' '); buf.write(suffix); }
    }

    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
