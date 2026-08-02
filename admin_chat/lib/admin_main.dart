import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/admin_chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const AdminChatApp());
}

class AdminChatApp extends StatelessWidget {
  const AdminChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Admin Chat',
      theme: ThemeData(primarySwatch: Colors.green),
      // FIX: Changed from AdminChatScreen() to ChatScreen() and passed the required senderName
      home: const ChatScreen(senderName: 'Admin'),
    );
  }
}
