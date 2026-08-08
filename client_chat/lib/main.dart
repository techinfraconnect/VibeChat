// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'socket_service.dart';
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

  final isolateFlnp = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await isolateFlnp.initialize(
    const InitializationSettings(android: androidInit),
  );

  const channel = AndroidNotificationChannel(
    'vibechat_channel',
    'VibeChat Notifications',
    description: 'Notifications for incoming messages and calls',
    importance: Importance.max,
    playSound: true,
  );
  await isolateFlnp
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  if (message.data['type'] == 'cancel_call') {
    await isolateFlnp.cancel(8888);
    return;
  }

  final title =
      message.notification?.title ?? message.data['title'] ?? 'VibeChat';
  final body = message.notification?.body ?? message.data['body'] ?? '';
  final isCall = message.data['type'] == 'call';

  const androidDetails = AndroidNotificationDetails(
    'vibechat_channel',
    'VibeChat Notifications',
    channelDescription: 'Notifications for incoming messages and calls',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.call,
  );

  int notifId = isCall ? 8888 : DateTime.now().millisecond;
  await isolateFlnp.show(
    notifId,
    title,
    body,
    const NotificationDetails(android: androidDetails),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp().timeout(const Duration(seconds: 3));
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    print("⚠️ Firebase initialization error: $e");
  }

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  await flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(android: initializationSettingsAndroid),
  );

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
  final SocketService _socketService = SocketService();
  bool isConnected = false;

  @override
  void initState() {
    super.initState();
    _connectToServer();
  }

  void _connectToServer() {
    _socketService.initSocket();

    _socketService.socket.onConnect((_) {
      print('🟢 Connected to server successfully!');
      if (mounted) setState(() => isConnected = true);
      _initializePushNotifications();
    });

    _socketService.socket.onConnectError(
      (err) => print('❌ Connect Error: $err'),
    );
    _socketService.socket.onError((err) => print('❌ Error: $err'));
    _socketService.socket.onDisconnect((_) {
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
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      String? token = await messaging.getToken();
      if (token != null) {
        print('📱 FCM Token retrieved: $token');
        _socketService.socket.emit('register_fcm_token', {
          'role': 'client',
          'token': token,
        });
      }

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (message.data['type'] == 'cancel_call') {
          flutterLocalNotificationsPlugin.cancel(8888);
          return;
        }

        final title =
            message.notification?.title ??
            message.data['title'] ??
            'New Message';
        final body = message.notification?.body ?? message.data['body'] ?? '';

        const AndroidNotificationDetails androidDetails =
            AndroidNotificationDetails(
              'vibechat_channel',
              'VibeChat Notifications',
              channelDescription:
                  'Notifications for incoming messages and calls',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              fullScreenIntent: true,
            );

        flutterLocalNotificationsPlugin.show(
          DateTime.now().millisecond,
          title,
          body,
          const NotificationDetails(android: androidDetails),
        );
      });
    } catch (e) {
      print("⚠️ Notification initialization failed: $e");
    }
  }

  @override
  void dispose() {
    _socketService.dispose();
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
    return ClientChatScreen(socket: _socketService.socket);
  }
}
