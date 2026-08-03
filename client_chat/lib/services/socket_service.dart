import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  late IO.Socket socket;
  bool _isInitialized = false;

  void initSocket(String username) {
    if (_isInitialized) return;

    socket = IO.io(
      'https://vibechat-server-vo3f.onrender.com',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    socket.connect();

    socket.onConnect((_) {
      print('====================================');
      print('🟢 CLIENT SOCKET CONNECTED SUCCESSFULLY');
      print('====================================');
    });

    socket.onConnectError((data) => print('❌ CLIENT SOCKET ERROR: $data'));

    _isInitialized = true;
  }
}
