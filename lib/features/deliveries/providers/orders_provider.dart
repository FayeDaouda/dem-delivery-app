import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/orders_repository.dart';

// ─── Repository provider ───────────────────────────────────────────────────
final ordersRepositoryProvider = Provider<OrdersRepository>((_) => OrdersRepository());

// ─── Available orders ──────────────────────────────────────────────────────
class AvailableOrdersNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() => _fetch();

  OrdersRepository get _repo => ref.read(ordersRepositoryProvider);

  Future<List<Map<String, dynamic>>> _fetch() => _repo.getAvailableOrders();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> acceptOrder(String orderId) async {
    await _repo.acceptOrder(orderId);
    await refresh();
  }
}

final availableOrdersProvider =
    AsyncNotifierProvider<AvailableOrdersNotifier, List<Map<String, dynamic>>>(
  AvailableOrdersNotifier.new,
);

// ─── My orders (historique) ────────────────────────────────────────────────
final myOrdersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.read(ordersRepositoryProvider).getMyOrders();
});

// ─── Order detail ──────────────────────────────────────────────────────────
final orderDetailProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, orderId) {
  return ref.read(ordersRepositoryProvider).getOrderById(orderId);
});

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
