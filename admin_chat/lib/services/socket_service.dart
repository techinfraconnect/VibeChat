import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../screens/call_screen.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  late io.Socket socket;
  late String currentUserId;
  GlobalKey<NavigatorState>? _navigatorKey;

  void initSocket(String userId, GlobalKey<NavigatorState> navigatorKey) {
    currentUserId = userId;
    _navigatorKey = navigatorKey;

    // Change to your machine's Local IP or Server domain
    socket = io.io('http://192.168.1.15:3000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket.connect();

    socket.onConnect((_) {
      debugPrint('[SocketService] Admin Connected. Registering ID: $userId');
      socket.emit('register', {'userId': userId});
    });

    // Global listener for incoming call notification
    socket.on('incoming_call', (data) {
      debugPrint('[SocketService] Admin received incoming_call: $data');

      final String caller = data['callerId'] ?? 'Client';
      final bool isVideo = data['isVideoCall'] ?? true;

      if (_navigatorKey?.currentState != null) {
        _navigatorKey!.currentState!.push(
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

    socket.on('user_offline', (data) {
      debugPrint('[SocketService] User is offline: $data');
      if (_navigatorKey?.currentContext != null) {
        ScaffoldMessenger.of(_navigatorKey!.currentContext!).showSnackBar(
          const SnackBar(content: Text('Client is currently offline.')),
        );
      }
    });
  }

  void initiateCall({required String receiverId, required bool isVideoCall}) {
    debugPrint('[SocketService] Initiating call to $receiverId');
    socket.emit('call_user', {
      'callerId': currentUserId,
      'callerName': 'Admin',
      'receiverId': receiverId,
      'isVideoCall': isVideoCall,
    });
  }
}
