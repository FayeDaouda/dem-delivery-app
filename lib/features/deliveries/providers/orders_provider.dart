import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/orders_repository.dart';

// ─── Repository provider ───────────────────────────────────────────────────
final ordersRepositoryProvider = Provider<OrdersRepository>((_) => OrdersRepository());

// ─── Available orders ──────────────────────────────────────────────────────
class AvailableOrdersNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async => [];

  OrdersRepository get _repo => ref.read(ordersRepositoryProvider);

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.getAvailableOrders());
  }

  Future<void> acceptOrder(String orderId) async {
    await _repo.acceptOrder(orderId);
    await refresh();
  }

  /// Reçu via WebSocket — injecte une course dispatchée en temps réel.
  /// Ignoré si une course est déjà affichée (ne pas écraser).
  void injectSocketOrder(Map<String, dynamic> order) {
    final current = state.value ?? [];
    if (current.isEmpty) {
      state = AsyncData([order]);
    }
  }

  /// Retire une course par son id (refusée ou expirée).
  void removeOrder(String orderId) {
    final current = state.value ?? [];
    state = AsyncData(current.where((o) => o['id'] != orderId).toList());
  }

  /// MODE DEV — injecte une fausse commande sans appel API
  void injectDevOrder() {
    state = AsyncData([
      {
        'id': 'dev-order-001',
        'orderType': 'DELIVERY',
        'status': 'PENDING',
        'price': 2500,
        'pickupAddress': 'Cité Keur Gorgui, Dakar',
        'deliveryAddress': 'Marché Sandaga, Dakar',
        'pickupLatitude': 14.7120,
        'pickupLongitude': -17.4680,
        'deliveryLatitude': 14.6941,
        'deliveryLongitude': -17.4442,
        'clientName': 'Moussa Diallo',
        'clientPhone': '+221771234567',
        'description': 'Colis fragile — 2 boîtes',
      }
    ]);
  }

  void clearDevOrder() {
    state = const AsyncData([]);
  }

  /// Vide l'état après acceptation d'une course (évite la réapparition au retour home).
  void clear() {
    state = const AsyncData([]);
  }
}

final availableOrdersProvider =
    AsyncNotifierProvider<AvailableOrdersNotifier, List<Map<String, dynamic>>>(
  AvailableOrdersNotifier.new,
);

// ─── Order detail ──────────────────────────────────────────────────────────
final orderDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, orderId) {
  return ref.read(ordersRepositoryProvider).getOrderById(orderId);
});

// ─── Tracking minimisé (client revenu à l'accueil pendant une course active) ─
final trackingMinimizedProvider = StateProvider<bool>((_) => false);

// ─── Active order for driver (in progress) ────────────────────────────────
class ActiveOrderNotifier extends AsyncNotifier<Map<String, dynamic>?> {
  @override
  Future<Map<String, dynamic>?> build() async => null;

  OrdersRepository get _repo => ref.read(ordersRepositoryProvider);

  Future<void> pickup(String orderId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.pickupOrder(orderId));
  }

  Future<void> deliver(String orderId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.deliverOrder(orderId));
  }
}

final activeOrderProvider =
    AsyncNotifierProvider<ActiveOrderNotifier, Map<String, dynamic>?>(
  ActiveOrderNotifier.new,
);
