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
      'https://vibechat-server-vo3f.onrender.com:443',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .build(),
    );

    socket.connect();

    socket.onConnect((_) {
      print('🟢 Client Socket Connected: ${socket.id} as $username');
      socket.emit('register_user', username);
    });

    socket.onConnectError((data) => print('❌ Client Connect Error: $data'));
    socket.onError((data) => print('❌ Client Socket Error: $data'));

    _isInitialized = true;
  }
}
