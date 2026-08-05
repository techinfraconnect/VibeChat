import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/socket_service.dart';
import 'screens/admin_chat_screen.dart';

final GlobalKey<NavigatorState> adminNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init warning: $e');
  }

  // IP Address note: Use 10.0.2.2 for Android Emulator, or your local machine IP (e.g. 192.168.x.x) for physical phone
  SocketService().initSocket(
    'admin',
    adminNavigatorKey,
    serverUrl: 'http://10.0.2.2:3000',
  );

  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Admin Chat',
      navigatorKey: adminNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const AdminChatScreen(),
    );
  }
}
