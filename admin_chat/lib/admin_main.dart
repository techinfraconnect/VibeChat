import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/socket_service.dart';
import 'main.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Pass options explicitly so it doesn't crash without google-services.json
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init error (ignored if already initialized): $e');
  }

  // Initialize WebSockets before running app
  SocketService().initSocket('admin', adminNavigatorKey);

  runApp(const AdminApp());
}
