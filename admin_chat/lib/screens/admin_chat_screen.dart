import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../services/socket_service.dart';
import 'call_screen.dart';

class AdminChatScreen extends StatefulWidget {
  final String senderName;
  final io.Socket socket;

  const AdminChatScreen({
    super.key,
    required this.senderName,
    required this.socket,
  });

  @override
  State<AdminChatScreen> createState() => _AdminChatScreenState();
}

class _AdminChatScreenState extends State<AdminChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _listenToChatMessages();
  }

  void _listenToChatMessages() {
    widget.socket.on('receive_message', (data) {
      if (mounted) {
        setState(() {
          _messages.add({
            'sender': data['sender'] ?? 'Client',
            'message': data['message'] ?? '',
            'isMe': false,
          });
        });
      }
    });
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    final text = _messageController.text.trim();
    widget.socket.emit('send_message', {
      'sender': widget.senderName,
      'receiver': 'client_123',
      'message': text,
    });

    setState(() {
      _messages.add({
        'sender': widget.senderName,
        'message': text,
        'isMe': true,
      });
    });

    _messageController.clear();
  }

  void _startCall(bool isVideo) {
    const String targetClient = 'client_123'; // Target Client User ID

    // 1. Emit call_user event via SocketService to alert the receiving app
    SocketService().initiateCall(
      receiverId: targetClient,
      isVideoCall: isVideo,
    );

    // 2. Navigate Admin to CallScreen as Caller
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallScreen(
          callerName: widget.senderName,
          targetUser: targetClient,
          isVideoCall: isVideo,
          isCaller: true,
          socket: widget.socket,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone),
            tooltip: 'Audio Call',
            onPressed: () => _startCall(false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            tooltip: 'Video Call',
            onPressed: () => _startCall(true),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg['isMe'] == true;
                return Align(
                  alignment: isMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4.0),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14.0,
                      vertical: 10.0,
                    ),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.blue : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: Text(
                      msg['message'] ?? '',
                      style: TextStyle(
                        color: isMe ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
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
