import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  late IO.Socket socket;
  bool _isInitialized = false;

  void initSocket(String username) {
    if (_isInitialized) return;

    // Manual connect approach is much more stable in Flutter
    socket = IO.io(
      'https://vibechat-server-vo3f.onrender.com',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect() // Disable auto-connect
          .build(),
    );

    // Connect manually
    socket.connect();

    socket.onConnect((_) {
      print('====================================');
      print('🟢 ADMIN SOCKET CONNECTED SUCCESSFULLY');
      print('====================================');
    });

    socket.onConnectError((data) => print('❌ ADMIN SOCKET ERROR: $data'));

    _isInitialized = true;
  }
}
