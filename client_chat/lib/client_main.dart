import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/socket_service.dart';
import 'screens/client_chat_screen.dart';

final GlobalKey<NavigatorState> clientNavigatorKey =
    GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init warning: $e');
  }

  SocketService().initSocket(
    'client_123',
    clientNavigatorKey,
    serverUrl: 'http://10.0.2.2:3000',
  );

  runApp(const ClientApp());
}

class ClientApp extends StatelessWidget {
  const ClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Client Chat',
      navigatorKey: clientNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.green),
      home: const ClientChatScreen(),
    );
  }
}
