import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
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
    _setupSocketListeners();
  }

  void _setupSocketListeners() {
    widget.socket.off('receive_message');
    widget.socket.off('incoming_call');

    widget.socket.on('receive_message', (data) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(Map<String, dynamic>.from(data));
      });
    });

    widget.socket.on('incoming_call', (data) {
      debugPrint('🔔 CLIENT RECEIVED INCOMING CALL');
      if (!mounted) {
        return;
      }
      if (data['callerName'] == widget.senderName) {
        return; // Prevent self-calling echo
      }
      _showIncomingCallDialog(Map<String, dynamic>.from(data));
    });
  }

  void _showIncomingCallDialog(Map<String, dynamic> data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text("Incoming Call from ${data['callerName']}"),
        content: Text(
          "Type: ${data['isVideoCall'] == true ? 'Video Call' : 'Audio Call'}",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.socket.emit('call_rejected');
            },
            child: const Text("Decline", style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              // 1. Close the dialog
              Navigator.pop(ctx);

              // 2. We DO NOT emit 'call_accepted' here anymore.
              // The CallScreen will handle it once the media is ready.

              // 3. Open the call screen
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CallScreen(
                    callerName: data['callerName'],
                    targetUser: data['callerName'],
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
    };

    widget.socket.emit('send_message', messageData);

    setState(() {
      _messages.add(messageData);
    });

    _messageController.clear();
  }

  void _initiateCall(bool isVideo) {
    widget.socket.emit('call_invite', {
      'callerName': widget.senderName,
      'isVideoCall': isVideo,
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CallScreen(
          callerName: widget.senderName,
          targetUser: "admin",
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
        title: const Text("Client Chat"),
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
                Expanded(child: TextField(controller: _messageController)),
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
