import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../../core/api/api_client.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_theme.dart';

const _dakar = LatLng(14.6937, -17.4441);

class HomeDriverScreen extends StatefulWidget {
  const HomeDriverScreen({super.key});

  @override
  State<HomeDriverScreen> createState() => _HomeDriverScreenState();
}

class _HomeDriverScreenState extends State<HomeDriverScreen> {
  Map<String, dynamic>? _user;
  bool _isAvailable = false;
  bool _togglingAvailability = false;
  List<dynamic> _availableOrders = [];
  bool _loadingOrders = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await AuthStorage.getUser();
    if (mounted) {
      setState(() {
        _user = user;
        _isAvailable = user?['isAvailable'] ?? false;
      });
      if (_isAvailable) _loadAvailableOrders();
    }
  }

  Future<void> _toggleAvailability() async {
    setState(() => _togglingAvailability = true);
    try {
      final res = await ApiClient.dio.patch('/users/driver/availability');
      final newAvailability = res.data['isAvailable'] as bool;

      // Mettre à jour le stockage local
      if (_user != null) {
        _user!['isAvailable'] = newAvailability;
        await AuthStorage.saveUser(_user!);
      }

      if (mounted) {
        setState(() => _isAvailable = newAvailability);
        if (newAvailability) _loadAvailableOrders();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur. Réessayez.')),
        );
      }
    } finally {
      if (mounted) setState(() => _togglingAvailability = false);
    }
  }

  Future<void> _loadAvailableOrders() async {
    setState(() => _loadingOrders = true);
    try {
      final res = await ApiClient.dio.get('/orders/available');
      if (mounted) setState(() => _availableOrders = res.data as List);
    } on DioException {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingOrders = false);
    }
  }

  Future<void> _acceptOrder(String orderId) async {
    await ApiClient.dio.patch('/orders/$orderId/accept');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Commande acceptée !')),
      );
      _loadAvailableOrders();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Carte plein écran
          FlutterMap(
            options: const MapOptions(initialCenter: _dakar, initialZoom: 13),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.dem.app',
              ),
            ],
          ),

          // Header
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 10,
                          color: _isAvailable ? AppColors.online : AppColors.offline,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isAvailable ? 'En ligne' : 'Hors ligne',
                          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      await AuthStorage.clear();
                      if (mounted) context.go('/phone');
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withOpacity(0.95),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.logout, color: AppColors.textSecondary, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom sheet driver
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Toggle ON/OFF
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bonjour, ${_user?['name'] ?? 'Driver'} 👋',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isAvailable ? 'Vous recevez des commandes' : 'Activez pour recevoir des courses',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                      const Spacer(),
                      _togglingAvailability
                          ? const SizedBox(
                              height: 32,
                              width: 32,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            )
                          : GestureDetector(
                              onTap: _toggleAvailability,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: 64,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: _isAvailable ? AppColors.primary : AppColors.card,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: AnimatedAlign(
                                  duration: const Duration(milliseconds: 300),
                                  alignment: _isAvailable ? Alignment.centerRight : Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.all(4),
                                    width: 26,
                                    height: 26,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ],
                  ),

                  // Commandes disponibles
                  if (_isAvailable) ...[
                    const SizedBox(height: 16),
                    const Divider(color: AppColors.card),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text(
                          'Courses disponibles',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        if (_loadingOrders)
                          const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          GestureDetector(
                            onTap: _loadAvailableOrders,
                            child: const Icon(Icons.refresh, color: AppColors.primary, size: 20),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_availableOrders.isEmpty)
                      const Text(
                        'Aucune course pour l\'instant...',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      )
                    else
                      ...(_availableOrders.take(3).map((order) => _OrderCard(
                            order: order,
                            onAccept: () => _acceptOrder(order['id']),
                          ))),
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
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.delivery_dining, color: AppColors.primary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order['pickupAddress'] ?? '',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '→ ${order['deliveryAddress'] ?? ''}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${order['price']?.toInt()} F',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: onAccept,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Accepter',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
