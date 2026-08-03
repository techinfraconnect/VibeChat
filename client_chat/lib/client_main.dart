import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/client_chat_screen.dart';
import 'services/socket_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Initialize WebSocket connection and register as Client
  SocketService().initSocket('Client');

  runApp(const ClientChatApp());
}

class ClientChatApp extends StatelessWidget {
  const ClientChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Client Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: ClientChatScreen(
        senderName: 'Client',
        socket: SocketService().socket,
      ),
    );
  }
}
