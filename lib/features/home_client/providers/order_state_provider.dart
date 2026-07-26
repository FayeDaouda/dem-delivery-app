import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/services/socket_service.dart';
import '../../deliveries/data/orders_repository.dart';
import '../../deliveries/providers/orders_provider.dart';
import 'order_state.dart';

// ── Provider (family par orderId) ─────────────────────────────────────────────
final clientOrderStateProvider = StateNotifierProvider.family<
    ClientOrderNotifier, ClientOrderState, String>(
  (ref, orderId) {
    final notifier = ClientOrderNotifier(
      orderId: orderId,
      repo: ref.read(ordersRepositoryProvider),
    );
    notifier._init();
    return notifier;
  },
);

// ── StateNotifier ─────────────────────────────────────────────────────────────
class ClientOrderNotifier extends StateNotifier<ClientOrderState> {
  final String orderId;
  final OrdersRepository repo;

  StreamSubscription<Map<String, dynamic>>? _statusSub;
  StreamSubscription<Map<String, dynamic>>? _locationSub;
  StreamSubscription<Map<String, dynamic>>? _offlineSub;
  StreamSubscription<Map<String, dynamic>>? _onlineSub;
  StreamSubscription<Map<String, dynamic>>? _unreachableSub;
  StreamSubscription<Map<String, dynamic>>? _searchingSub;
  StreamSubscription<Map<String, dynamic>>? _adminCancelledSub;
  StreamSubscription<Map<String, dynamic>>? _paymentConfirmedSub;
  String? cancelReason;
  Timer? _pollTimer;
  Timer? _retryLocationTimer;
  DateTime? _lastNotifUpdate;

  ClientOrderNotifier({
    required this.orderId,
    required this.repo,
    Map<String, dynamic>? initialData,
  }) : super(ClientOrderState(
          orderData: initialData,
          phase: initialData?['status'] as String? ?? 'ACCEPTED',
          isLoading: initialData == null,
        ));

  void _init() {
    _fetchOrder();
    _connectSocket();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 20), (_) => _fetchOrder());
    _retryLocationTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (state.driverLocation == null) {
        SocketService.instance.requestDriverLocation(orderId);
      }
    });
  }

  // ── Fetch DB ─────────────────────────────────────────────────────────────────
  Future<void> _fetchOrder() async {
    try {
      final results = await Future.wait([
        repo.getOrderById(orderId),
        repo.getMyOrders(),
      ]);
      if (!mounted) return;

      final order = results[0] as Map<String, dynamic>;
      final all = results[1] as List<Map<String, dynamic>>;
      const activeStatuses = ['ACCEPTED', 'PICKED_UP', 'IN_TRANSIT'];
      final others = all.where((o) {
        final s = (o['status'] as String? ?? '').toUpperCase();
        return activeStatuses.contains(s) && o['id'] != orderId;
      }).toList();

      state = state.copyWith(
        orderData: order,
        phase: order['status'] as String? ?? state.phase,
        otherActiveOrders: others,
        isLoading: false,
      );
    } catch (_) {
      if (mounted) state = state.copyWith(isLoading: false);
    }
  }

  // ── Socket listeners ─────────────────────────────────────────────────────────
  void _connectSocket() {
    _statusSub = SocketService.instance.onOrderStatusUpdated.listen((data) {
      if (!mounted || data['orderId'] != orderId) return;
      final newPhase = data['status'] as String?;
      if (newPhase != null) {
        state = state.copyWith(phase: newPhase);
        _notifyStatusChange(newPhase);
      }
    });

    _locationSub = SocketService.instance.onDriverLocation.listen((data) {
      if (!mounted || data['orderId'] != orderId) return;
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      final newLoc = LatLng(lat, lng);

      // ETA live
      final eta = _computeEta(lat, lng);

      state = state.copyWith(
        driverLocation: newLoc,
        driverStatus: DriverStatus.online,
        offlineSinceNull: true,
        etaMin: eta,
      );

      _maybeNotify(lat, lng, eta);
    });

    _offlineSub = SocketService.instance.onDriverOffline.listen((data) {
      if (!mounted || data['orderId'] != orderId) return;
      final ts = data['lastSeenAt'] as String?;
      state = state.copyWith(
        driverStatus: DriverStatus.offline,
        driverOfflineSince: ts != null ? DateTime.tryParse(ts) : DateTime.now(),
      );
    });

    _onlineSub = SocketService.instance.onDriverOnline.listen((data) {
      if (!mounted || data['orderId'] != orderId) return;
      state = state.copyWith(
        driverStatus: DriverStatus.online,
        offlineSinceNull: true,
      );
    });

    _unreachableSub = SocketService.instance.onDriverUnreachable.listen((data) {
      if (!mounted || data['orderId'] != orderId) return;
      state = state.copyWith(driverStatus: DriverStatus.unreachable);
    });

    _searchingSub = SocketService.instance.onOrderSearching.listen((data) {
      if (!mounted || data['orderId'] != orderId) return;
      state = state.copyWith(
        driverStatus: DriverStatus.searching,
        driverLocationNull: true,
        offlineSinceNull: true,
      );
    });

    _adminCancelledSub = SocketService.instance.onOrderAdminCancelled.listen((data) {
      if (!mounted || data['orderId'] != orderId) return;
      cancelReason = data['reason'] as String?;
      state = state.copyWith(phase: 'CANCELLED');
    });

    // Paiement en ligne SamirPay confirmé (recharge déclenchée par le client
    // lui-même ou QR affiché par le livreur) — recharge depuis la DB plutôt
    // que de patcher `paymentStatus` localement, pour rester source-de-vérité
    // unique avec le reste de l'état (montant, éventuels autres champs mis à
    // jour côté serveur au même moment).
    _paymentConfirmedSub = SocketService.instance.onOrderPaymentConfirmed.listen((data) {
      if (!mounted || data['orderId'] != orderId) return;
      // Notification systémique même si le client n'est plus sur l'écran de
      // paiement (parti sur un autre onglet, ou revenu de Wave/OM sans
      // rouvrir la feuille) — sinon rien ne l'informe explicitement que son
      // paiement est passé, contrairement aux autres étapes de la course
      // (voir _notifyStatusChange). Ce provider (family, pas autoDispose)
      // reste vivant tant que l'app tourne, même après avoir quitté l'écran
      // de suivi de cette commande.
      final amount = (data['amount'] as num?)?.toInt();
      NotificationService.showSystemNotification(
        title: 'Paiement confirmé',
        body: amount != null ? 'Votre paiement de $amount FCFA a bien été reçu.' : 'Votre paiement a bien été reçu.',
      );
      NotificationService.playAlertSound();
      _fetchOrder();
    });
  }

  // ── Notification système à chaque étape clé ────────────────────────────────
  void _notifyStatusChange(String phase) {
    final messages = {
      'PICKED_UP':  ('Colis récupéré', 'Votre livreur est en route vers vous.'),
      'IN_TRANSIT': ('En route', 'Votre livreur se dirige vers la destination.'),
      'DELIVERED':  ('Livraison effectuée', 'Votre colis a été livré avec succès !'),
      'CANCELLED':  ('Course annulée', 'Votre course a été annulée.'),
    };
    final msg = messages[phase];
    if (msg != null) {
      NotificationService.showSystemNotification(title: msg.$1, body: msg.$2);
      NotificationService.playAlertSound();
    }
  }

  // ── Calcul ETA côté client (rough, 25 km/h moyen) ────────────────────────
  int? _computeEta(double driverLat, double driverLng) {
    final order = state.orderData;
    if (order == null) return null;
    final isPickedUp = state.phase == 'PICKED_UP';
    final targetLat = isPickedUp
        ? (order['deliveryLatitude'] as num?)?.toDouble()
        : (order['pickupLatitude'] as num?)?.toDouble();
    final targetLng = isPickedUp
        ? (order['deliveryLongitude'] as num?)?.toDouble()
        : (order['pickupLongitude'] as num?)?.toDouble();
    if (targetLat == null || targetLng == null) return null;
    final dist =
        Geolocator.distanceBetween(driverLat, driverLng, targetLat, targetLng);
    return (dist / 416).round();
  }

  // ── Notification persistante (throttle 60s) ───────────────────────────────
  void _maybeNotify(double lat, double lng, int? etaMin) {
    if (etaMin == null) return;
    final now = DateTime.now();
    if (_lastNotifUpdate != null &&
        now.difference(_lastNotifUpdate!).inSeconds < 60) {
      return;
    }
    _lastNotifUpdate = now;

    final order = state.orderData;
    if (order == null) return;
    final isPickedUp = state.phase == 'PICKED_UP';
    final targetName = isPickedUp
        ? (order['deliveryAddress']?.toString() ?? 'Destination')
        : (order['pickupAddress']?.toString() ?? 'Pickup');
    final statusText = isPickedUp
        ? 'Le livreur est en route vers vous'
        : 'Le livreur récupère votre commande';
    final etaText = etaMin > 0 ? ' (~$etaMin min)' : ' (Proche)';
    NotificationService.showOngoingNotification(
      id: 8888, title: statusText, body: '$targetName$etaText',
    );
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _locationSub?.cancel();
    _offlineSub?.cancel();
    _onlineSub?.cancel();
    _unreachableSub?.cancel();
    _searchingSub?.cancel();
    _adminCancelledSub?.cancel();
    _paymentConfirmedSub?.cancel();
    _pollTimer?.cancel();
    _retryLocationTimer?.cancel();
    super.dispose();
  }
}
