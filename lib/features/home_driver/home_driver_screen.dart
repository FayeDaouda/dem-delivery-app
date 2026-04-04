import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../features/deliveries/providers/orders_provider.dart';
import '../../features/profile/providers/profile_provider.dart';

const _dakar = LatLng(14.6937, -17.4441);

class HomeDriverScreen extends ConsumerStatefulWidget {
  const HomeDriverScreen({super.key});

  @override
  ConsumerState<HomeDriverScreen> createState() => _HomeDriverScreenState();
}

class _HomeDriverScreenState extends ConsumerState<HomeDriverScreen> {
  String? _mapStyle;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    // Charger le profil depuis le stockage local au démarrage
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileProvider.notifier).fetchProfile();
    });
  }

  Future<void> _loadMapStyle() async {
    final style = await rootBundle.loadString('assets/map_style_waze.json');
    if (mounted) setState(() => _mapStyle = style);
  }

  Future<void> _toggleAvailability() async {
    try {
      await ref.read(profileProvider.notifier).toggleAvailability();
      final isAvailable = ref.read(profileProvider).isAvailable;
      if (isAvailable) ref.read(availableOrdersProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _acceptOrder(String orderId) async {
    try {
      await ref.read(availableOrdersProvider.notifier).acceptOrder(orderId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Commande acceptée !')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final isAvailable = profile.isAvailable;
    final ordersAsync = ref.watch(availableOrdersProvider);

    return Scaffold(
      body: Stack(
        children: [
          // ── Carte Google Maps style Waze ──
          GoogleMap(
            initialCameraPosition: const CameraPosition(target: _dakar, zoom: 14),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
            style: _mapStyle,
            onMapCreated: (_) {},
          ),

          // ── Header ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Toggle disponibilité (gauche)
                  GestureDetector(
                    onTap: profile.isLoading ? null : _toggleAvailability,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isAvailable ? AppColors.primary : AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8)],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 8, color: isAvailable ? Colors.white : AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Text(
                            isAvailable ? 'En ligne' : 'Hors ligne',
                            style: TextStyle(
                              color: isAvailable ? Colors.white : AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          profile.isLoading
                              ? const SizedBox(width: 28, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Switch.adaptive(
                                  value: isAvailable,
                                  onChanged: (_) => _toggleAvailability(),
                                  activeThumbColor: Colors.white,
                                  activeTrackColor: Colors.white.withValues(alpha: 0.4),
                                  inactiveThumbColor: AppColors.textSecondary,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Icône profil (droite)
                  GestureDetector(
                    onTap: () => context.push('/driver/profile'),
                    child: Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8)],
                      ),
                      child: const Icon(Icons.person_outline, color: AppColors.textPrimary, size: 22),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom sheet ──
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 20)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bonjour${profile.name.isNotEmpty ? ', ${profile.name}' : ''} 👋',
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isAvailable ? 'Vous recevez des commandes' : 'Activez pour recevoir des courses',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (isAvailable) ...[
                    const SizedBox(height: 16),
                    const Divider(color: AppColors.card),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Courses disponibles',
                            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => ref.read(availableOrdersProvider.notifier).refresh(),
                          child: const Icon(Icons.refresh, color: AppColors.primary, size: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ordersAsync.when(
                      loading: () => const SizedBox(
                        height: 40,
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                      error: (e, _) => Text(e.toString(),
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      data: (orders) => orders.isEmpty
                          ? const Text('Aucune course pour l\'instant...',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
                          : Column(
                              children: orders
                                  .take(3)
                                  .map((order) => _OrderCard(
                                        order: order,
                                        onAccept: () => _acceptOrder(order['id']),
                                      ))
                                  .toList(),
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onAccept;

  const _OrderCard({required this.order, required this.onAccept});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.delivery_dining, color: AppColors.primary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order['pickupAddress'] ?? '',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('→ ${order['deliveryAddress'] ?? ''}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${(order['price'] as num?)?.toInt()} F',
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: onAccept,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                  child: const Text('Accepter',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
