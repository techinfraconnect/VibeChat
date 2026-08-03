import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/admin_chat_screen.dart';
import 'services/socket_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Initialize WebSocket connection and register as Admin
  SocketService().initSocket('Admin');

  runApp(const AdminChatApp());
}

class AdminChatApp extends StatelessWidget {
  const AdminChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Admin Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.green),
      home: AdminChatScreen(
        senderName: 'Admin',
        socket: SocketService().socket,
      ),
    );
  }
}
