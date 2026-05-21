import 'package:google_maps_flutter/google_maps_flutter.dart';

enum DriverStatus { online, offline, unreachable, searching }

/// État métier d'une commande côté client.
/// Séparé de l'état de vue (carte, route, marqueurs) qui reste local au widget.
class ClientOrderState {
  final Map<String, dynamic>? orderData;
  final String phase;             // 'ACCEPTED' | 'PICKED_UP' | 'DELIVERED' | 'CANCELLED'
  final LatLng? driverLocation;
  final int? etaMin;
  final DriverStatus driverStatus;
  final DateTime? driverOfflineSince;
  final List<Map<String, dynamic>> otherActiveOrders;
  final bool isLoading;

  const ClientOrderState({
    this.orderData,
    this.phase = 'ACCEPTED',
    this.driverLocation,
    this.etaMin,
    this.driverStatus = DriverStatus.online,
    this.driverOfflineSince,
    this.otherActiveOrders = const [],
    this.isLoading = true,
  });

  ClientOrderState copyWith({
    Map<String, dynamic>? orderData,
    String? phase,
    LatLng? driverLocation,
    bool driverLocationNull = false,
    int? etaMin,
    bool etaNull = false,
    DriverStatus? driverStatus,
    DateTime? driverOfflineSince,
    bool offlineSinceNull = false,
    List<Map<String, dynamic>>? otherActiveOrders,
    bool? isLoading,
  }) =>
      ClientOrderState(
        orderData: orderData ?? this.orderData,
        phase: phase ?? this.phase,
        driverLocation:
            driverLocationNull ? null : (driverLocation ?? this.driverLocation),
        etaMin: etaNull ? null : (etaMin ?? this.etaMin),
        driverStatus: driverStatus ?? this.driverStatus,
        driverOfflineSince: offlineSinceNull
            ? null
            : (driverOfflineSince ?? this.driverOfflineSince),
        otherActiveOrders: otherActiveOrders ?? this.otherActiveOrders,
        isLoading: isLoading ?? this.isLoading,
      );
}
