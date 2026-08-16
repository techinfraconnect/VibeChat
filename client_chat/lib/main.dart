// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

// PRO FIX: Explicit imports clear the "CallKitParams isn't defined" compiler errors
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';

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

  final data = message.data;
  if (data.isEmpty) {
    return;
  }

  if (data['type'] == 'cancel_call') {
    await FlutterCallkitIncoming.endAllCalls();
    await isolateFlnp.cancel(8888);
    return;
  }

  if (data['type'] == 'call') {
    CallKitParams callKitParams = CallKitParams(
      id: data['callId'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      nameCaller: data['callerName'] ?? 'Caller',
      appName: 'VibeChat Client',
      avatar: 'https://i.pravatar.cc/100',
      handle: data['isVideoCall'] == 'true' ? 'Video Call' : 'Audio Call',
      type: data['isVideoCall'] == 'true' ? 1 : 0,
      duration: 30000,
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Missed call',
      ),
      extra: <String, dynamic>{
        'isVideoCall': data['isVideoCall'],
        'callId': data['callId'],
      },
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0955fa',
        actionColor: '#4CAF50',
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 2,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: true,
        supportsHolding: true,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
  }
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
  late io.Socket socket;
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

    socket.onConnectError((err) {
      print('❌ Connect Error: $err');
    });

    socket.onError((err) {
      print('❌ Error: $err');
    });

    socket.onDisconnect((_) {
      if (mounted) {
        setState(() {
          isConnected = false;
        });
      }
    });

    Future.delayed(const Duration(seconds: 4), () {
      if (!isConnected && mounted) {
        setState(() {
          isConnected = true;
        });
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
        socket.emit('register_fcm_token', {'role': 'client', 'token': token});
      }

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (message.data['type'] == 'cancel_call') {
          flutterLocalNotificationsPlugin.cancel(8888);
          FlutterCallkitIncoming.endAllCalls();
          return;
        }

        if (message.data['type'] == 'call') {
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
    socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isConnected) {
      return const Scaffold(
        backgroundColor: Color(0xFF0C0C0E),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
