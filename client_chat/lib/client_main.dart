import 'package:flutter/material.dart';
//import 'package:firebase_core/firebase_core.dart';
import 'screens/client_chat_screen.dart';
import 'services/socket_service.dart';

// Create a global navigator key if needed, or simply let the app run.
final GlobalKey<NavigatorState> clientNavigatorKey =
    GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ensure you initialize Firebase if you are using it
  // await Firebase.initializeApp();

  // FIX 1: Pass only the username to initSocket
  SocketService().initSocket('Client');

  runApp(const ClientChatApp());
}

class ClientChatApp extends StatelessWidget {
  const ClientChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Client Chat',
      navigatorKey: clientNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      // FIX 2: Pass the required 'senderName' and 'socket' parameters
      home: ClientChatScreen(
        senderName: 'Client',
        socket: SocketService().socket,
      ),
    );
  }
}
