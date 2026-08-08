import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/client_text.dart';

class _NavItem {
  final IconData outline;
  final IconData filled;
  final String label;
  const _NavItem(this.outline, this.filled, this.label);
}

const _items = [
  _NavItem(Icons.home_outlined,                   Icons.home_rounded,             'Accueil'),
  _NavItem(Icons.two_wheeler_outlined,             Icons.two_wheeler,              'Livraisons'),
  _NavItem(Icons.place_outlined,                  Icons.place,                    'Adresses'),
  _NavItem(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet,   'Finances'),
  _NavItem(Icons.person_outline,                  Icons.person,                   'Compte'),
];

class DemProNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const DemProNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: List.generate(_items.length, (i) {
              final item     = _items[i];
              final selected = i == currentIndex;
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primary.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          selected ? item.filled : item.outline,
                          color: selected
                              ? AppColors.primary
                              : AppColors.lightIconMuted,
                          size: 22,
                        ),
                      ),
                      const SizedBox(height: 5),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        style: ClientText.micro.copyWith(
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                          color: selected
                              ? AppColors.primary
                              : AppColors.lightIconMuted,
                        ),
                        child: Text(item.label),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
