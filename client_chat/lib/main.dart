// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'screens/client_chat_screen.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const ClientApp());
}

class ClientApp extends StatelessWidget {
  const ClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VibeChat Client',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MainChatWrapper(),
    );
  }
}

class MainChatWrapper extends StatefulWidget {
  const MainChatWrapper({super.key});

  @override
  State<MainChatWrapper> createState() => _MainChatWrapperState();
}

class _MainChatWrapperState extends State<MainChatWrapper> {
  late io.Socket socket;
  final String userRole = 'client';
  bool isConnected = false;

  @override
  void initState() {
    super.initState();
    _connectToServer();
  }

  void _connectToServer() {
    socket = io.io(
      'https://vibechat-server-vo3f.onrender.com/',
      <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
        'timeout': 10000,
      },
    );

    socket.connect();

    socket.onConnect((_) {
      print('🟢 Connected to server successfully!');
      if (mounted) {
        setState(() {
          isConnected = true;
        });
      }
      _initializePushNotifications();
    });

    socket.onConnectError((err) => print('❌ Connect Error: $err'));
    socket.onError((err) => print('❌ Error: $err'));

    socket.onDisconnect((_) {
      if (mounted) {
        setState(() {
          isConnected = false;
        });
      }
    });

    // Fallback timer to prevent hanging on splash screen if server is spinning up
    Future.delayed(const Duration(seconds: 5), () {
      if (!isConnected && mounted) {
        print('⚠️ Connection timeout reached, forcing entry to chat screen.');
        setState(() {
          isConnected = true;
        });
      }
    });
  }

  void _initializePushNotifications() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted notification permissions.');
    } else {
      print('User declined or did not accept permission.');
      return;
    }

    String? token = await messaging.getToken();
    if (token != null) {
      print('📱 FCM Token retrieved: $token');
      socket.emit('register_fcm_token', {'role': userRole, 'token': token});
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Foreground notification received: ${message.notification?.title}');
    });
  }

  @override
  void dispose() {
    socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isConnected) {
      return Scaffold(
        backgroundColor: const Color(0xFF0C0C0E),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(color: Colors.blue),
              SizedBox(height: 16),
              Text(
                'Connecting to VibeChat Server...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }
    return ClientChatScreen(socket: socket);
  }
}
