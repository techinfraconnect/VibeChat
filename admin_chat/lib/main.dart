import 'package:flutter/material.dart';
import 'screens/admin_chat_screen.dart';
import 'services/socket_service.dart';

// Global navigator key
final GlobalKey<NavigatorState> adminNavigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AdminApp());
}

class AdminApp extends StatefulWidget {
  const AdminApp({super.key});

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  @override
  void initState() {
    super.initState();
    // FIX 1: Pass only the single required username string 'admin'
    SocketService().initSocket('admin');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VibeChat Admin',
      navigatorKey: adminNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      // FIX 2: Pass required named parameters 'senderName' and 'socket'
      home: AdminChatScreen(
        senderName: 'admin',
        socket: SocketService().socket,
      ),
    );
  }
}
