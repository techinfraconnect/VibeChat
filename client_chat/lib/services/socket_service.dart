import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  // Singleton pattern to keep a single active connection across the app
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  late IO.Socket socket;

  void connect() {
    // Replace with your computer's local IP address if testing locally (e.g., 'http://192.168.1.x:3000')
    // Or your deployed server URL
    socket = IO.io('http://YOUR_SERVER_URL:3000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket.connect();

    socket.onConnect((_) {
      print('🟢 Connected to Socket.io Server: ${socket.id}');
    });

    socket.onDisconnect((_) {
      print('🔴 Disconnected from Socket.io Server');
    });

    socket.onConnectError((data) => print('⚠️ Connect Error: $data'));
  }

  // Send a message to the server
  void sendMessage(String event, Map<String, dynamic> data) {
    socket.emit(event, data);
  }

  // Listen for incoming messages
  void onMessage(String event, Function(dynamic) callback) {
    socket.on(event, (data) => callback(data));
  }

  // Disconnect manually if needed
  void disconnect() {
    socket.disconnect();
  }
}
