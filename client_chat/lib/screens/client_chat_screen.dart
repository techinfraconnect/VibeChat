import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'call_screen.dart';

class ClientChatScreen extends StatefulWidget {
  final String senderName;
  final IO.Socket socket;

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
    _setupSocketListeners();
  }

  void _setupSocketListeners() {
    widget.socket.off('receive_message');
    widget.socket.off('incoming_call');

    widget.socket.on('receive_message', (data) {
      if (!mounted) return;
      setState(() {
        _messages.add(Map<String, dynamic>.from(data));
      });
    });

    widget.socket.on('incoming_call', (data) {
      if (!mounted) return;
      // Do not trigger popup if this app initiated the call
      if (data['callerName']?.toString().toLowerCase() ==
          widget.senderName.toLowerCase()) {
        return;
      }
      _showIncomingCallDialog(Map<String, dynamic>.from(data));
    });
  }

  void _showIncomingCallDialog(Map<String, dynamic> data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text("Incoming Call from ${data['callerName'] ?? 'Admin'}"),
        content: Text(
          "Type: ${data['isVideoCall'] == true ? 'Video Call' : 'Audio Call'}",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.socket.emit('call_rejected', {
                'targetUser': data['callerName'],
              });
            },
            child: const Text("Decline", style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.socket.emit('call_accepted', {
                'callerName': widget.senderName,
                'targetUser': data['callerName'],
              });
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CallScreen(
                    callerName: data['callerName'] ?? 'Admin',
                    targetUser: data['callerName'] ?? 'Admin',
                    isVideoCall: data['isVideoCall'] ?? false,
                    isCaller: false,
                    socket: widget.socket,
                  ),
                ),
              );
            },
            child: const Text("Accept"),
          ),
        ],
      ),
    );
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;
    final messageData = {
      'sender': widget.senderName,
      'message': _messageController.text.trim(),
      'timestamp': DateTime.now().toIso8601String(),
    };
    widget.socket.emit('send_message', messageData);
    _messageController.clear();
  }

  void _initiateCall(bool isVideo) {
    const String targetUser = 'Admin'; // Client calls Admin

    widget.socket.emit('call_invite', {
      'callerName': widget.senderName,
      'targetUser': targetUser,
      'isVideoCall': isVideo,
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallScreen(
          callerName: targetUser,
          targetUser: targetUser,
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
        title: Text("Client Chat (${widget.senderName})"),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () => _initiateCall(false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () => _initiateCall(true),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                bool isMe = msg['sender'] == widget.senderName;
                return ListTile(
                  title: Align(
                    alignment: isMe
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isMe ? Colors.blue[100] : Colors.grey[300],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(msg['message'] ?? ''),
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
