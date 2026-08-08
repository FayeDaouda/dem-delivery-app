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
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.lightBorder)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
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
                      Icon(
                        selected ? item.filled : item.outline,
                        color: selected ? AppColors.primary : AppColors.lightIconMuted,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: ClientText.label.copyWith(
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? AppColors.primary : AppColors.lightIconMuted,
                        ),
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
