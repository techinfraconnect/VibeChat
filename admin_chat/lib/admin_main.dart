import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/socket_service.dart';
import 'main.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  SocketService().initSocket('admin', adminNavigatorKey);

  runApp(const AdminApp());
}
