// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'screens/client_chat_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  print("Handling background message: ${message.messageId}");

  // PRO FIX: Extract from message.data for background Data-Only payloads
  final title =
      message.notification?.title ?? message.data['title'] ?? 'VibeChat';
  final body =
      message.notification?.body ?? message.data['body'] ?? 'New Notification';

  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'vibechat_channel',
    'VibeChat Notifications',
    channelDescription: 'Notifications for incoming messages and calls',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    fullScreenIntent: true, // Wakes the device screen when locked!
  );

  const NotificationDetails details = NotificationDetails(
    android: androidDetails,
  );

  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecond,
    title,
    body,
    details,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fail-safe timeout to prevent splash screen freezes
  try {
    await Firebase.initializeApp().timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        print("⚠️ Firebase init timed out. Continuing app startup...");
        throw Exception("Firebase timeout");
      },
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    print("⚠️ Firebase initialization error: $e");
  }

  // Initialize local notifications
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // CRITICAL FOR PHYSICAL ANDROID PHONES (Vivo/Honor): Create the high-importance channel
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'vibechat_channel',
    'VibeChat Notifications',
    description: 'Notifications for incoming messages and calls',
    importance: Importance.max,
    playSound: true,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  runApp(const ClientApp());
}

class ClientApp extends StatelessWidget {
  const ClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VibeChat Client',
      navigatorKey: navigatorKey,
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
      if (mounted) setState(() => isConnected = true);
      _initializePushNotifications();
    });

    socket.onConnectError((err) => print('❌ Connect Error: $err'));
    socket.onError((err) => print('❌ Error: $err'));
    socket.onDisconnect((_) {
      if (mounted) setState(() => isConnected = false);
    });

    Future.delayed(const Duration(seconds: 4), () {
      if (!isConnected && mounted) {
        setState(() => isConnected = true);
      }
    });
  }

  void _initializePushNotifications() async {
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('User granted notification permissions.');
      }

      String? token = await messaging.getToken();
      if (token != null) {
        print('📱 FCM Token retrieved: $token');
        socket.emit('register_fcm_token', {'role': userRole, 'token': token});
      }

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('Foreground notification received.');
        // PRO FIX: Check message.data payload when app is open
        final title =
            message.notification?.title ??
            message.data['title'] ??
            'New Message';
        final body = message.notification?.body ?? message.data['body'] ?? '';

        _showLocalNotification(title, body);
      });
    } catch (e) {
      print("⚠️ Notification initialization failed: $e");
    }
  }

  void _showLocalNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'vibechat_channel',
          'VibeChat Notifications',
          channelDescription: 'Notifications for incoming messages and calls',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          fullScreenIntent: true,
        );
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );
    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond,
      title,
      body,
      details,
    );
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
