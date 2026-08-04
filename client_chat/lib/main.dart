import 'package:flutter/material.dart';
import 'screens/client_chat_screen.dart';
import 'services/socket_service.dart';

final GlobalKey<NavigatorState> clientNavigatorKey =
    GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ClientApp());
}

class ClientApp extends StatefulWidget {
  const ClientApp({super.key});

  @override
  State<ClientApp> createState() => _ClientAppState();
}

class _ClientAppState extends State<ClientApp> {
  @override
  void initState() {
    super.initState();
    // Initialize socket connection globally for Client
    SocketService().initSocket('client_123', clientNavigatorKey);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VibeChat Client',
      navigatorKey: clientNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.green),
      home: ClientChatScreen(
        senderName: 'Client',
        socket: SocketService().socket,
      ),
    );
  }
}
