import 'package:flutter/material.dart';
import '../theme/dem_pro_colors.dart';

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
  final bool darkMode;
  const DemProNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.darkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    final bg      = darkMode ? DemProColors.bg2      : Colors.white;
    final border  = darkMode ? DemProColors.bg3      : const Color(0xFFE2E8F0);
    final inactive = darkMode ? const Color(0xFF8EABC5) : const Color(0xFF94A3B8);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: border)),
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
                        color: selected ? DemProColors.accent : inactive,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? DemProColors.accent : inactive,
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
