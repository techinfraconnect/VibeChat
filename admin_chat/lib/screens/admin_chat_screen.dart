import 'package:flutter/material.dart';
import '../services/socket_service.dart';
import 'call_screen.dart';

class AdminChatScreen extends StatefulWidget {
  const AdminChatScreen({super.key});

  @override
  State<AdminChatScreen> createState() => _AdminChatScreenState();
}

class _AdminChatScreenState extends State<AdminChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final String _targetUser = 'client_123'; // Target client ID

  @override
  void initState() {
    super.initState();
    _setupSocketListeners();
  }

  void _setupSocketListeners() {
    final socket = SocketService().socket;
    if (socket != null) {
      socket.off('receive_message');
      socket.on('receive_message', (data) {
        if (mounted) {
          setState(() {
            _messages.add(Map<String, dynamic>.from(data));
          });
        }
      });
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final messageData = {
      'senderId': 'admin',
      'receiverId': _targetUser,
      'text': text,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    SocketService().socket?.emit('send_message', messageData);
    _messageController.clear();
  }

  void _startCall({required bool isVideoCall}) {
    final socket = SocketService().socket;
    if (socket == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callerName: 'admin',
          targetUser: _targetUser,
          isVideoCall: isVideoCall,
          isCaller: true,
          socket: socket,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat with $_targetUser'),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone),
            onPressed: () => _startCall(isVideoCall: false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () => _startCall(isVideoCall: true),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg['senderId'] == 'admin';
                return Align(
                  alignment: isMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.blue : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      msg['text'] ?? '',
                      style: TextStyle(
                        color: isMe ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
