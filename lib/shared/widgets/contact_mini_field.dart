import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../../core/utils/input_formatters.dart';

/// Carte "Expéditeur"/"Destinataire" — nom + téléphone, bouton "Moi" et accès
/// aux contacts du téléphone. Même traitement que les champs départ/
/// destination (AddressField) : fond blanc quasi-opaque plutôt qu'un lavis
/// translucide, pour rester lisible quel que soit le fond derrière. Partagé
/// entre "Livraison simple/Express" et "Livraison groupée".
class ContactMiniField extends StatelessWidget {
  final String label;
  final Color dotColor;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final VoidCallback onPick;
  final VoidCallback? onPickMe;
  final VoidCallback? onPhoneComplete;
  const ContactMiniField({
    super.key,
    required this.label,
    required this.dotColor,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.onPick,
    this.onPickMe,
    this.onPhoneComplete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: dotColor.withValues(alpha: 0.75), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: dotColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (onPickMe != null)
                GestureDetector(
                  onTap: onPickMe,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: dotColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Moi',
                      style: TextStyle(
                        color: dotColor,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              GestureDetector(
                onTap: onPick,
                child: const Icon(
                  Icons.contacts_rounded,
                  color: AppColors.textMuted,
                  size: 26,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: nameCtrl,
            inputFormatters: [NameInputFormatter()],
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(color: AppColors.textDark, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Nom complet',
              hintStyle: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
              ),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 12, right: 8),
                child: Icon(
                  Icons.person_outline_rounded,
                  color: AppColors.textMuted,
                  size: 18,
                ),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 0,
                minHeight: 0,
              ),
              fillColor: Colors.black.withValues(alpha: 0.045),
              filled: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 13,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [DigitsOnlyFormatter()],
            style: const TextStyle(color: AppColors.textDark, fontSize: 14),
            onChanged: (v) {
              if (v.length >= 9) onPhoneComplete?.call();
            },
            decoration: InputDecoration(
              hintText: 'Numéro de téléphone',
              hintStyle: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: Icon(Icons.phone_outlined, color: dotColor, size: 18),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 0,
                minHeight: 0,
              ),
              prefixText: '+221 ',
              prefixStyle: ClientText.bodyStrong.copyWith(color: dotColor),
              fillColor: Colors.black.withValues(alpha: 0.045),
              filled: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 13,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
