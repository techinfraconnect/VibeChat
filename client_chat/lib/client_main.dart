import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/client_chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const ClientChatApp());
}

class ClientChatApp extends StatelessWidget {
  const ClientChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Client Chat',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ClientChatScreen(),
    );
  }
}
