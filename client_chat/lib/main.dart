import 'package:flutter/material.dart';
//import 'package:firebase_core/firebase_core.dart';
import 'screens/client_chat_screen.dart';
import 'services/socket_service.dart';

// Create a global navigator key if needed for background navigation
final GlobalKey<NavigatorState> clientNavigatorKey =
    GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (Uncomment the line below if you are using Firebase)
  // await Firebase.initializeApp();

  // FIX 1: Pass only the username (String) to initSocket, as defined in socket_service.dart
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
      // FIX 2: Pass the strictly required 'senderName' and 'socket' parameters
      home: ClientChatScreen(
        senderName: 'Client',
        socket: SocketService().socket,
      ),
    );
  }
}
