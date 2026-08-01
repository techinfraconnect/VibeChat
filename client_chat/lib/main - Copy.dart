import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/client_chat_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

void main() async {
  print("APP_START: Main function started.");

  WidgetsFlutterBinding.ensureInitialized();
  print("APP_START: Widgets bound.");

  try {
    print("APP_START: Initializing Firebase...");
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print("APP_START: Firebase initialized successfully!");
  } catch (e) {
    print("APP_START ERROR: Failed to initialize Firebase: $e");
  }

  runApp(const ClientChatApp());
}

// Top-level background message handler
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

class ClientChatApp extends StatelessWidget {
  const ClientChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vibe Chat Client',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ClientChatScreen(),
    );
  }
}
