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
      <String, dynamic>{
        'transports': ['websocket', 'polling'],
        'autoConnect': true,
        'reconnection': true,
        'reconnectionAttempts': 10,
        'reconnectionDelay': 1000,
      },
    );

    socket.connect();

    socket.onConnect((_) {
      print('🟢 Client Socket Connected: ${socket.id} as $username');
      socket.emit('register_user', username);
    });

    socket.onReconnect((_) {
      print('🔄 Client Socket Reconnected as $username');
      socket.emit('register_user', username);
    });

    socket.onConnectError(
      (data) => print('❌ Client Socket Connect Error: $data'),
    );
    socket.onError((data) => print('❌ Client Socket Error: $data'));

    _isInitialized = true;
  }
}
