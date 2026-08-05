import 'package:flutter/foundation.dart'; // Required for debugPrint
import 'package:socket_io_client/socket_io_client.dart'
    as io; // FIX: Changed 'IO' to 'io'

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  late io.Socket socket; // FIX: Changed 'IO.Socket' to 'io.Socket'
  bool _isInitialized = false;

  void initSocket(String username) {
    if (_isInitialized) return;

    // FIX: Changed 'IO.io' and 'IO.OptionBuilder' to 'io'
    socket = io.io(
      'https://vibechat-server-vo3f.onrender.com',
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .disableAutoConnect() // We manually connect below
          .build(),
    );

    // Register listeners BEFORE connecting
    // FIX: Replaced all 'print' statements with 'debugPrint'
    socket.onConnect((_) {
      debugPrint('\n=================================');
      debugPrint('🟢 $username SOCKET CONNECTED SUCCESSFULLY');
      debugPrint('SOCKET ID: ${socket.id}');
      debugPrint('=================================\n');
    });

    socket.onConnectError(
      (data) => debugPrint('\n❌ SOCKET CONNECT ERROR: $data\n'),
    );
    socket.onError((data) => debugPrint('\n❌ SOCKET ERROR: $data\n'));
    socket.onDisconnect((_) => debugPrint('\n🔴 SOCKET DISCONNECTED\n'));

    // Execute connection
    socket.connect();

    _isInitialized = true;
  }
}
