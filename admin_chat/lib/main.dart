import 'package:flutter/material.dart';
import 'screens/admin_chat_screen.dart';
import 'services/socket_service.dart';

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
    // Initialize socket connection globally for Admin
    SocketService().initSocket('admin', adminNavigatorKey);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VibeChat Admin',
      navigatorKey: adminNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const AdminChatScreen(),
    );
  }
}
