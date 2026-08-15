import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/dem_toast.dart';

/// Demande l'accès aux contacts du téléphone puis ouvre un sélecteur
/// (recherche + liste) — remplit [nameCtrl]/[phoneCtrl] avec le contact
/// choisi. Partagé entre tous les flux de commande (Simple/Express/Groupée).
Future<void> pickContact(
  BuildContext context, {
  required TextEditingController nameCtrl,
  required TextEditingController phoneCtrl,
}) async {
  final status = await FlutterContacts.permissions.request(PermissionType.read);
  final granted =
      status == PermissionStatus.granted || status == PermissionStatus.limited;

  if (!granted) {
    if (!context.mounted) return;
    showDemToast(context, 'Accès aux contacts refusé', isError: true);
    return;
  }
  final contacts = await FlutterContacts.getAll(
    properties: {ContactProperty.name, ContactProperty.phone},
  );
  if (!context.mounted) return;
  _showContactPicker(
    context,
    contacts,
    nameCtrl: nameCtrl,
    phoneCtrl: phoneCtrl,
  );
}

void _showContactPicker(
  BuildContext context,
  List<Contact> contacts, {
  required TextEditingController nameCtrl,
  required TextEditingController phoneCtrl,
}) {
  String q = '';
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setSB) {
        final filtered = contacts
            .where(
              (c) =>
                  q.isEmpty ||
                  (c.displayName ?? '').toLowerCase().contains(q.toLowerCase()),
            )
            .toList();
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (_, sc) => Container(
            decoration: const BoxDecoration(
              // Dégradé cyan (comme DEM Pro) au lieu d'un bleu marine uni.
              gradient: AppColors.gradientSplash,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Choisir un contact',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: TextField(
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Rechercher...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                      fillColor: Colors.white.withValues(alpha: 0.14),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (v) => setSB(() => q = v),
                  ),
                ),
                Divider(
                  color: AppColors.textSecondary.withValues(alpha: 0.2),
                  height: 1,
                ),
                Expanded(
                  child: ListView.builder(
                    controller: sc,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      final phoneObj = c.phones.isNotEmpty
                          ? c.phones.first
                          : null;
                      if (phoneObj == null) return const SizedBox.shrink();
                      final cleaned = phoneObj.number
                          .replaceAll(RegExp(r'[\s\-\(\)]'), '')
                          .replaceFirst('+221', '');
                      final name = c.displayName ?? 'Contact';
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primary.withValues(
                            alpha: 0.12,
                          ),
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          cleaned,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          nameCtrl.text = name;
                          phoneCtrl.text = cleaned;
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
