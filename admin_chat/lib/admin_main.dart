import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/socket_service.dart';
import 'main.dart'; // Provides adminNavigatorKey and AdminApp

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Pass BOTH 'admin' ID AND adminNavigatorKey
  SocketService().initSocket('admin', adminNavigatorKey);

  runApp(const AdminApp());
}
