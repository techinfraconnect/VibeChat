import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  late IO.Socket socket;
  bool _isInitialized = false;

  void initSocket(String username) {
    if (_isInitialized) return;

    // The Fix: Use OptionBuilder to explicitly set the transport and connection parameters.
    socket = IO.io(
      'https://vibechat-server-vo3f.onrender.com:443', // Explicitly add :443 to bypass the port 0 bug
      IO.OptionBuilder()
          .setTransports(['websocket']) // Required for Flutter
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(1000)
          .build(),
    );

    socket.connect();

    socket.onConnect((_) {
      print('🟢 Socket Connected: ${socket.id} as $username');
      socket.emit('register_user', username);
    });

    socket.onReconnect((_) {
      print('🔄 Socket Reconnected as $username');
      socket.emit('register_user', username);
    });

    socket.onConnectError((data) => print('❌ Socket Connect Error: $data'));
    socket.onError((data) => print('❌ Socket Error: $data'));

    _isInitialized = true;
  }
}
