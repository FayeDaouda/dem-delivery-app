/// Préfixes mobiles valides au Sénégal : Orange (77/78), Free (76/75), Expresso (70).
final _senegalMobileRegex = RegExp(r'^(70|75|76|77|78)\d{7}$');

/// [digits] doit être les 9 chiffres du numéro, sans l'indicatif +221.
bool isValidSenegalMobile(String digits) => _senegalMobileRegex.hasMatch(digits);
