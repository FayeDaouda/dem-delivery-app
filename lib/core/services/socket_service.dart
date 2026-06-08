import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

const _serverUrl = 'https://api.dem.sn';

/// Service WebSocket singleton — reçoit les courses en temps réel.
///
/// Utilisation :
///   SocketService.instance.connect(token)
///   SocketService.instance.onNewOrder.listen(...)
///   SocketService.instance.onOrderExpired.listen(...)
class SocketService {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final SocketService instance = SocketService._();
  SocketService._();

  io.Socket? _socket;

  // ── Streams publics ────────────────────────────────────────────────────────
  final _newOrderController             = StreamController<Map<String, dynamic>>.broadcast();
  final _expiredOrderController         = StreamController<String>.broadcast();
  final _reconnectController            = StreamController<void>.broadcast();
  final _orderAcceptedController        = StreamController<Map<String, dynamic>>.broadcast();
  final _orderStatusUpdatedController   = StreamController<Map<String, dynamic>>.broadcast();
  final _driverLocationController       = StreamController<Map<String, dynamic>>.broadcast();
  final _driverOfflineController        = StreamController<Map<String, dynamic>>.broadcast();
  final _driverOnlineController         = StreamController<Map<String, dynamic>>.broadcast();
  final _orderSearchingController       = StreamController<Map<String, dynamic>>.broadcast();
  final _driverUnreachableController    = StreamController<Map<String, dynamic>>.broadcast();
  final _orderCancelledController       = StreamController<Map<String, dynamic>>.broadcast();
  final _orderAdminCancelledController  = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onNewOrder             => _newOrderController.stream;
  Stream<String>               get onOrderExpired          => _expiredOrderController.stream;
  Stream<void>                 get onReconnect             => _reconnectController.stream;
  Stream<Map<String, dynamic>> get onOrderAccepted         => _orderAcceptedController.stream;
  Stream<Map<String, dynamic>> get onOrderStatusUpdated    => _orderStatusUpdatedController.stream;
  Stream<Map<String, dynamic>> get onDriverLocation        => _driverLocationController.stream;
  Stream<Map<String, dynamic>> get onDriverOffline         => _driverOfflineController.stream;
  Stream<Map<String, dynamic>> get onDriverOnline          => _driverOnlineController.stream;
  // Incidents driver — manque de heartbeat prolongé
  Stream<Map<String, dynamic>> get onOrderSearching        => _orderSearchingController.stream;
  Stream<Map<String, dynamic>> get onDriverUnreachable     => _driverUnreachableController.stream;
  // Annulations (client + driver)
  Stream<Map<String, dynamic>> get onOrderCancelled        => _orderCancelledController.stream;
  Stream<Map<String, dynamic>> get onOrderAdminCancelled   => _orderAdminCancelledController.stream;

  bool get isConnected => _socket?.connected ?? false;

  void ping({double? lat, double? lng}) {
    final data = (lat != null && lng != null) ? {'lat': lat, 'lng': lng} : null;
    _socket?.emit('driver:ping', data);
  }

  void emitDriverLocation(double lat, double lng, String orderId) {
    _socket?.emit('driver:location', {'lat': lat, 'lng': lng, 'orderId': orderId});
  }

  void requestDriverLocation(String orderId) {
    _socket?.emit('client:requestDriverLocation', {'orderId': orderId});
  }

  // ── Connexion ──────────────────────────────────────────────────────────────
  void connect(String token) {
    if (_socket?.connected == true) return; // déjà connecté

    _socket?.dispose();

    _socket = io.io(
      _serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .enableReconnection()
          // Délai progressif : 2s → 4s → 8s → max 30s (backoff exponentiel)
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(30000)
          // Infini : la socket essaie jusqu'à ce qu'elle réussisse (pas de capitulation)
          .setReconnectionAttempts(double.maxFinite.toInt())
          // Timeout de connexion : 10s (réduit depuis défaut 20s)
          .setTimeout(10000)
          .build(),
    );

    _socket!
      ..on('connect', (_) {
        if (kDebugMode) debugPrint('[SOCKET] Connecté à $_serverUrl');
      })
      ..on('reconnect', (_) {
        if (kDebugMode) debugPrint('[SOCKET] Reconnecté — rafraîchissement des courses');
        _reconnectController.add(null);
      })
      ..on('disconnect', (reason) {
        if (kDebugMode) debugPrint('[SOCKET] Déconnecté — $reason');
      })
      ..on('connect_error', (err) {
        if (kDebugMode) debugPrint('[SOCKET] Erreur connexion — $err');
      })
      ..on('order:new', (data) {
        if (data is Map) {
          _newOrderController.add(Map<String, dynamic>.from(data));
        }
      })
      ..on('order:expired', (data) {
        if (data is Map && data['orderId'] != null) {
          _expiredOrderController.add(data['orderId'] as String);
        }
      })
      ..on('order:taken', (data) {
        // Un autre driver du broadcast a accepté — même comportement qu'une expiration
        if (data is Map && data['orderId'] != null) {
          _expiredOrderController.add(data['orderId'] as String);
        }
      })
      ..on('order:accepted', (data) {
        if (data is Map) {
          _orderAcceptedController.add(Map<String, dynamic>.from(data));
        }
      })
      ..on('order:status_updated', (data) {
        if (data is Map) {
          _orderStatusUpdatedController.add(Map<String, dynamic>.from(data));
        }
      })
      ..on('driver:location', (data) {
        if (data is Map) {
          _driverLocationController.add(Map<String, dynamic>.from(data));
        }
      })
      ..on('driver:offline', (data) {
        if (data is Map) {
          _driverOfflineController.add(Map<String, dynamic>.from(data));
        }
      })
      ..on('driver:online', (data) {
        if (data is Map) {
          _driverOnlineController.add(Map<String, dynamic>.from(data));
        }
      })
      ..on('order:searching', (data) {
        if (data is Map) {
          _orderSearchingController.add(Map<String, dynamic>.from(data));
        }
      })
      ..on('order:driver_unreachable', (data) {
        if (data is Map) {
          _driverUnreachableController.add(Map<String, dynamic>.from(data));
        }
      })
      ..on('order:cancelled', (data) {
        if (data is Map) {
          _orderCancelledController.add(Map<String, dynamic>.from(data));
        }
      })
      ..on('order:admin_cancelled', (data) {
        if (data is Map) {
          _orderAdminCancelledController.add(Map<String, dynamic>.from(data));
        }
      })
      ..connect();
  }

  // ── Déconnexion ────────────────────────────────────────────────────────────
  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }
}
