import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Notifier global ───────────────────────────────────────────────────────────
final _localeNotifier = ValueNotifier<String>('fr');

class LocaleService {
  static const _key = 'app_lang';

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _localeNotifier.value = prefs.getString(_key) ?? 'fr';
  }

  static Future<void> setLang(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, lang);
    _localeNotifier.value = lang;
  }

  static String get current => _localeNotifier.value;
  static ValueNotifier<String> get notifier => _localeNotifier;
}

// ── Traductions FR / EN ───────────────────────────────────────────────────────
class AppStrings {
  final String lang;
  const AppStrings(this.lang);

  static AppStrings get current => AppStrings(LocaleService.current);

  // ── Auth ──────────────────────────────────────────────────────────────────
  String get welcome         => _t('Bienvenue 👋',             'Welcome 👋');
  String get enterPhone      => _t('Entrez votre numéro pour continuer', 'Enter your number to continue');
  String get phoneLabel      => _t('Numéro de téléphone',      'Phone number');
  String get continueBtn     => _t('Continuer',                'Continue');
  String get verification    => _t('Vérification',             'Verification');
  String get codeSentTo      => _t('Code envoyé au',           'Code sent to');
  String get validate        => _t('Valider',                  'Validate');
  String get resendCode      => _t('Renvoyer',                 'Resend');
  String get notReceived     => _t('Pas reçu le code ?',       "Didn't receive the code?");

  // ── Profil ────────────────────────────────────────────────────────────────
  String get myProfile       => _t('Mon profil',               'My profile');
  String get information     => _t('Informations',             'Information');
  String get documents       => _t('Documents',                       'Documents');
  String get activity        => _t('Activité',                         'Activity');
  String get settings        => _t('Paramètres',                       'Settings');
  String get account         => _t('Compte',                           'Account');
  String get phoneNumber     => _t('Téléphone',                        'Phone');
  String get plate           => _t('Plaque d\'immatriculation',        'Registration plate');
  String get statusLabel     => _t('Statut',                   'Status');
  String get verified        => _t('Vérifié ✓',                'Verified ✓');
  String get notVerified     => _t('Non vérifié',              'Not verified');
  String get idCard          => _t("Carte d'identité",         'ID Card');
  String get license         => _t('Permis de conduire',       "Driver's license");
  String get docVerified     => _t('Vérifié',                  'Verified');
  String get docPending      => _t('À soumettre',              'To submit');
  String get historyTitle    => _t('Historique des courses',   'Delivery history');
  String get editPhone       => _t('Modifier numéro',          'Edit number');
  String get language        => _t('Langue',                   'Language');
  String get support         => _t('Support',                  'Support');
  String get logout          => _t('Se déconnecter',           'Log out');
  String get deleteAccount   => _t('Supprimer mon compte',     'Delete my account');
  String get deleteAccountTitle   => _t('Supprimer le compte', 'Delete account');
  String get deleteAccountWarning => _t(
    'Cette action est irréversible. Toutes vos données (profil, historique, documents) seront définitivement supprimées.',
    'This action is irreversible. All your data (profile, history, documents) will be permanently deleted.',
  );
  String get deleteAccountConfirm => _t('Supprimer définitivement', 'Delete permanently');
  String get deleteAccountSuccess => _t('Compte supprimé.', 'Account deleted.');
  String get french          => _t('Français',                 'French');
  String get english         => _t('Anglais',                  'English');
  String get wolof           => _t('Wolof',                    'Wolof');

  // ── Documents ─────────────────────────────────────────────────────────────
  String get idCardFrontLabel => _t("Carte d'identité — Recto", 'ID Card — Front');
  String get idCardBackLabel  => _t("Carte d'identité — Verso",  'ID Card — Back');
  String get licenseFrontLabel => _t('Permis — Recto',           'License — Front');
  String get licenseBackLabel  => _t('Permis — Verso',           'License — Back');
  String get uploadPhoto      => _t('Ajouter une photo',         'Add a photo');
  String get changePhoto      => _t('Changer la photo',          'Change photo');
  String get takePhoto        => _t('Prendre une photo',         'Take a photo');
  String get fromGallery      => _t('Choisir depuis la galerie', 'Choose from gallery');
  String get uploading        => _t('Envoi en cours…',           'Uploading…');
  String get uploadSuccess    => _t('Document envoyé !',         'Document uploaded!');

  // ── Support ───────────────────────────────────────────────────────────────
  String get callSupport     => _t('Appeler le support',         'Call support');
  String get sendEmail       => _t('Envoyer un email',           'Send email');
  String get whatsapp        => _t('WhatsApp',                   'WhatsApp');

  // ── Phone change ──────────────────────────────────────────────────────────
  String get newPhone        => _t('Nouveau numéro',             'New number');
  String get phoneChangeSent => _t('Demande envoyée. En attente de validation admin.', 'Request sent. Awaiting admin approval.');
  String get phonePending    => _t('Modification en attente de validation', 'Change pending approval');

  // ── Legal ─────────────────────────────────────────────────────────────────
  String get privacyPolicy   => _t('Politique de confidentialité', 'Privacy Policy');
  String get termsOfService  => _t('Conditions d\'utilisation',    'Terms of Service');

  // ── Common ────────────────────────────────────────────────────────────────
  String get cancel          => _t('Annuler',     'Cancel');
  String get save            => _t('Enregistrer', 'Save');
  String get close           => _t('Fermer',      'Close');
  String get retry           => _t('Réessayer',   'Retry');
  String get noData          => _t('Aucune donnée', 'No data');

  String _t(String fr, String en) => lang == 'en' ? en : fr;
}
