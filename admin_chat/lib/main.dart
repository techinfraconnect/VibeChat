import 'package:flutter/material.dart';
import 'screens/admin_chat_screen.dart';
import 'services/socket_service.dart';

final GlobalKey<NavigatorState> adminNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Socket Connection
  SocketService().initSocket();

  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VibeChat Admin',
      navigatorKey: adminNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: AdminChatScreen(
        senderName: 'Admin',
        socket: SocketService().socket,
      ),
    );
  }
}
