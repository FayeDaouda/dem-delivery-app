import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/client_text.dart';
import '../../core/utils/price_format.dart';
import '../../features/deliveries/data/orders_repository.dart';

/// Dialogue "Notez votre livreur" — affiché à la livraison d'une course
/// simple/Express ou à la fin d'une tournée groupée. Un seul composant
/// partagé (auparavant dupliqué au fil des écrans) pour ne jamais avoir à
/// corriger deux fois le même bug d'étoiles/commentaire.
Future<void> showDriverRatingDialog(
  BuildContext context, {
  required String orderId,
  required String driverId,
  double? amount,
  VoidCallback? onDone,
}) {
  int selectedRating = 5;
  final commentController = TextEditingController();

  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setDialogState) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            gradient: AppColors.gradientSplash,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 16),
              const Text(
                'Livraison effectuée !',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (amount != null) ...[
                const SizedBox(height: 6),
                Text(
                  formatFcfa(amount),
                  style: ClientText.title.copyWith(color: Colors.white),
                ),
              ],
              const SizedBox(height: 20),
              const Text(
                'Notez votre livreur',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final star = i + 1;
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedRating = star),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        star <= selectedRating ? Icons.star : Icons.star_border,
                        color: star <= selectedRating
                            ? AppColors.ratingGold
                            : Colors.white38,
                        size: 36,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: commentController,
                style: const TextStyle(color: Colors.white),
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Un commentaire ? (optionnel)',
                  hintStyle: const TextStyle(
                    color: Colors.white38,
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    final comment = commentController.text.trim().isEmpty
                        ? null
                        : commentController.text.trim();
                    try {
                      await OrdersRepository().rateDriver(
                        orderId: orderId,
                        driverId: driverId,
                        score: selectedRating,
                        comment: comment,
                      );
                    } catch (_) {}
                    onDone?.call();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Envoyer & Retour',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  onDone?.call();
                },
                child: const Text(
                  'Passer',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
