import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../deliveries/data/orders_repository.dart';
import '../../deliveries/providers/orders_provider.dart';
import 'order_state.dart';

final guestOrderStateProvider = StateNotifierProvider.family<
    GuestOrderNotifier, ClientOrderState, String>(
  (ref, orderId) {
    final notifier = GuestOrderNotifier(
      orderId: orderId,
      repo: ref.read(ordersRepositoryProvider),
    );
    notifier._init();
    return notifier;
  },
);

class GuestOrderNotifier extends StateNotifier<ClientOrderState> {
  final String orderId;
  final OrdersRepository repo;

  Timer? _pollTimer;

  GuestOrderNotifier({
    required this.orderId,
    required this.repo,
  }) : super(const ClientOrderState(isLoading: true));

  void _init() {
    _fetchOrder();
    // Short-polling HTTP pour le Guest, toutes les 10 secondes
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _fetchOrder());
  }

  Future<void> _fetchOrder() async {
    try {
      final order = await repo.getGuestOrder(orderId);
      if (!mounted) return;

      if (order['isExpired'] == true) {
        state = state.copyWith(
          orderData: order,
          phase: order['status'] as String?,
          isLoading: false,
        );
        _pollTimer?.cancel();
        return;
      }

      final phase = order['status'] as String?;
      LatLng? loc;
      int? eta;

      final driver = order['driver'] as Map<String, dynamic>?;
      if (driver != null) {
        final lat = (driver['latitude'] as num?)?.toDouble();
        final lng = (driver['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          loc = LatLng(lat, lng);
          eta = _computeEta(lat, lng, order);
        }
      }

      state = state.copyWith(
        orderData: order,
        phase: phase ?? state.phase,
        driverLocation: loc,
        driverLocationNull: loc == null,
        etaMin: eta ?? order['etaDeliveryMin'] as int?,
        isLoading: false,
      );
    } catch (_) {
      if (mounted) state = state.copyWith(isLoading: false);
    }
  }

  int? _computeEta(double driverLat, double driverLng, Map<String, dynamic> order) {
    final isPickedUp = order['status'] == 'PICKED_UP' || order['status'] == 'IN_TRANSIT';
    final targetLat = isPickedUp
        ? (order['deliveryLatitude'] as num?)?.toDouble()
        : (order['pickupLatitude'] as num?)?.toDouble();
    final targetLng = isPickedUp
        ? (order['deliveryLongitude'] as num?)?.toDouble()
        : (order['pickupLongitude'] as num?)?.toDouble();
    if (targetLat == null || targetLng == null) return null;
    final dist = Geolocator.distanceBetween(driverLat, driverLng, targetLat, targetLng);
    return (dist / 416).round();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
