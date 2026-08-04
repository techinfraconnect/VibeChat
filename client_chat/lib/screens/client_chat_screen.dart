import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../services/socket_service.dart';
import 'call_screen.dart';

class ClientChatScreen extends StatefulWidget {
  final String senderName;
  final io.Socket socket;

  const ClientChatScreen({
    super.key,
    required this.senderName,
    required this.socket,
  });

  @override
  State<ClientChatScreen> createState() => _ClientChatScreenState();
}

class _ClientChatScreenState extends State<ClientChatScreen> {
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
            'sender': data['sender'] ?? 'Admin',
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
      'receiver': 'admin',
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
    const String targetAdmin = 'admin'; // Target Admin User ID

    // 1. Emit call_user event via SocketService to alert the receiving app
    SocketService().initiateCall(receiverId: targetAdmin, isVideoCall: isVideo);

    // 2. Navigate Client to CallScreen as Caller
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallScreen(
          callerName: widget.senderName,
          targetUser: targetAdmin,
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
        title: const Text('Client Chat'),
        backgroundColor: Colors.green,
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
                      color: isMe ? Colors.green : Colors.grey[300],
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
                  icon: const Icon(Icons.send, color: Colors.green),
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
