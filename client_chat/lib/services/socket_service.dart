import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  late IO.Socket socket;
  bool _isInitialized = false;

  void initSocket(String username) {
    if (_isInitialized) return;

    // Standard URL without port overrides.
    // Allowing both polling and websocket ensures Render's load balancer accepts the connection.
    socket = IO.io(
      'https://vibechat-server-vo3f.onrender.com',
      <String, dynamic>{
        'transports': ['websocket', 'polling'],
        'autoConnect':
            false, // We will manually connect below to prevent race conditions
      },
    );

    // Register listeners BEFORE connecting
    socket.onConnect((_) {
      print('\n=================================');
      print('🟢 $username SOCKET CONNECTED SUCCESSFULLY');
      print('SOCKET ID: ${socket.id}');
      print('=================================\n');
    });

    socket.onConnectError((data) => print('\n❌ SOCKET CONNECT ERROR: $data\n'));
    socket.onError((data) => print('\n❌ SOCKET ERROR: $data\n'));
    socket.onDisconnect((_) => print('\n🔴 SOCKET DISCONNECTED\n'));

    // Execute connection
    socket.connect();

    _isInitialized = true;
  }
}
