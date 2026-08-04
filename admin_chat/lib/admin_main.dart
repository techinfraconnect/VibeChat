import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/admin_chat_screen.dart';
import 'services/socket_service.dart';
import 'main.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Initialize WebSocket connection (takes 0 positional arguments in admin_chat)
  SocketService().initSocket();

  runApp(const AdminApp());
}
