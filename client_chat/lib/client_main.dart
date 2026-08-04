import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/socket_service.dart';
import 'main.dart'; // Provides clientNavigatorKey and ClientApp

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Pass BOTH 'client_123' ID AND clientNavigatorKey
  SocketService().initSocket('client_123', clientNavigatorKey);

  runApp(const ClientApp());
}
