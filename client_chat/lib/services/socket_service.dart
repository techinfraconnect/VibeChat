import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../screens/call_screen.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  io.Socket? socket;
  String? currentUserId;
  GlobalKey<NavigatorState>? navigatorKey;

  void initSocket(
    String userId,
    GlobalKey<NavigatorState> navKey, {
    String serverUrl = 'http://10.0.2.2:3000',
  }) {
    currentUserId = userId;
    navigatorKey = navKey;

    socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    socket!.connect();

    socket!.onConnect((_) {
      debugPrint('[SocketService] Connected as $userId');
      socket!.emit('register', userId);
    });

    socket!.on('incoming_call', (data) {
      debugPrint('[SocketService] Incoming call data: $data');
      if (navigatorKey?.currentContext != null) {
        Navigator.push(
          navigatorKey!.currentContext!,
          MaterialPageRoute(
            builder: (_) => CallScreen(
              callerName: data['callerName'] ?? data['callerId'],
              targetUser: data['callerId'],
              isVideoCall: data['isVideoCall'] ?? true,
              isCaller: false,
              socket: socket!,
            ),
          ),
        );
      }
    });

    socket!.onDisconnect((_) => debugPrint('[SocketService] Disconnected'));
  }
}
