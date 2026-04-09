import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;

const _serverUrl = 'https://dem-delivery-backend.onrender.com';

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
  final _newOrderController     = StreamController<Map<String, dynamic>>.broadcast();
  final _expiredOrderController = StreamController<String>.broadcast();
  final _reconnectController    = StreamController<void>.broadcast();

  /// Émis quand le backend dispatche une nouvelle course à ce driver.
  Stream<Map<String, dynamic>> get onNewOrder     => _newOrderController.stream;

  /// Émis quand l'offre expire côté backend (orderId).
  Stream<String>               get onOrderExpired  => _expiredOrderController.stream;

  /// Émis à chaque reconnexion — le screen doit rafraîchir les courses.
  Stream<void>                 get onReconnect     => _reconnectController.stream;

  bool get isConnected => _socket?.connected ?? false;

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
          .setReconnectionDelay(3000)
          .setReconnectionAttempts(10)
          .build(),
    );

    _socket!
      ..on('connect', (_) {
        // ignore: avoid_print
        print('[SOCKET] Connecté à $_serverUrl');
      })
      ..on('reconnect', (_) {
        // ignore: avoid_print
        print('[SOCKET] Reconnecté — rafraîchissement des courses');
        _reconnectController.add(null);
      })
      ..on('disconnect', (reason) {
        // ignore: avoid_print
        print('[SOCKET] Déconnecté — $reason');
      })
      ..on('connect_error', (err) {
        // ignore: avoid_print
        print('[SOCKET] Erreur connexion — $err');
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
      ..connect();
  }

  // ── Déconnexion ────────────────────────────────────────────────────────────
  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }
}
