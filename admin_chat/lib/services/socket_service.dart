import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../screens/call_screen.dart';
import '../main.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  late io.Socket socket;

  void initSocket() {
    socket = io.io('http://192.168.1.15:3000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket.connect();

    socket.onConnect((_) {
      debugPrint('Admin connected to socket server');
      socket.emit('register', {'userId': 'admin'});
    });

    socket.on('incoming_call', (data) {
      debugPrint('Incoming call received in Admin App: $data');

      final String caller = data['callerId'] ?? 'Client';
      final bool isVideo = data['isVideoCall'] ?? true;

      if (adminNavigatorKey.currentState != null) {
        adminNavigatorKey.currentState!.push(
          MaterialPageRoute(
            builder: (context) => CallScreen(
              callerName: caller,
              targetUser: caller,
              isVideoCall: isVideo,
              isCaller: false,
              socket: socket,
            ),
          ),
        );
      }
    });
  }

  void initiateCall(String receiverId, bool isVideoCall) {
    socket.emit('call_user', {
      'callerId': 'admin',
      'receiverId': receiverId,
      'isVideoCall': isVideoCall,
    });
  }

  void disconnect() {
    socket.disconnect();
  }
}
