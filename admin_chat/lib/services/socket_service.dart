import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  late IO.Socket socket;

  void initSocket(String username) {
    socket = IO.io(
      'https://vibechat-server-vo3f.onrender.com',
      <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
      },
    );

    socket.connect();

    socket.onConnect((_) {
      print('🟢 Connected to global server: ${socket.id}');
      socket.emit('register_user', username);
    });

    socket.onConnectError((data) => print('❌ Connect Error: $data'));
    socket.onError((data) => print('❌ Socket Error: $data'));
  }
}
